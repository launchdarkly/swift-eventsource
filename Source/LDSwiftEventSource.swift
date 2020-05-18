import Foundation
import os.log

/// Error class that means the remote server returned an HTTP error.
public class UnsuccessfulResponseError: Error {
    /// The HTTP response code received
    public let responseCode: Int

    init(responseCode: Int) {
        self.responseCode = responseCode
    }
}

/// Protocol for an object that will receive SSE events.
public protocol EventHandler {
    /// EventSource calls this method when the stream connection has been opened.
    func onOpened()
    /// EventSource calls this method when the stream connection has been closed.
    func onClosed()
    /// EventSource calls this method when it has received a new event from the stream.
    func onMessage(event: String, messageEvent: MessageEvent)
    /// EventSource calls this method when it has received a comment line from the stream
    /// (any line starting with a colon).
    func onComment(comment: String)
    /// This method will be called for all exceptions that occur on the socket connection
    /// (including an {@link UnsuccessfulResponseError} if the server returns an unexpected HTTP status),
    /// but only after the ConnectionErrorHandler (if any) has processed it.  If you need to
    /// do anything that affects the state of the connection, use ConnectionErrorHandler.
    func onError(error: Error)
}

typealias ConnectionHandler = (setReconnectionTime: (TimeInterval) -> (), setLastEventId: (String) -> ())
/// Type for a function that will be notified when EventSource encounters a connection failure.
/// This is different from onError in that it will not be called for other kinds of errors; also,
/// it has the ability to tell EventSource to stop reconnecting.
public typealias ConnectionErrorHandler = (Error) -> ConnectionErrorAction

/// Potential actions a ConnectionErrorHandler can return
public enum ConnectionErrorAction {
    /// Specifies that the error should be logged normally and dispatched to the EventHandler.
    /// Connection retrying will proceed normally if appropriate.
    case proceed
    /// Specifies that the connection should be immediately shut down and not retried. The error
    ///  will not be dispatched to the EventHandler
    case shutdown
}

/// Enum values representing the states of an EventSource
public enum ReadyState: String, Equatable {
    /// The EventSource has not been started yet.
    case raw
    /// The EventSource is attempting to make a connection.
    case connecting
    /// The EventSource is active and the EventSource is listening for events.
    case open
    /// The connection has been closed or has failed, and the EventSource will attempt to reconnect.
    case closed
    /// The connection has been permanently closed and will not reconnect.
    case shutdown
}

/// Struct representing received event from the stream.
public struct MessageEvent: Equatable, Hashable {
    /// Returns the event data.
    public let data: String
    /// The last seen event id, or the event id set in the Config if none have been received.
    public let lastEventId: String?

    init(data: String, lastEventId: String? = nil) {
        self.data = data
        self.lastEventId = lastEventId
    }
}

public class EventSource: NSObject, URLSessionDataDelegate {

    private let config: Config

    private let delegateQueue: DispatchQueue = DispatchQueue(label: "ESDelegateQueue")
    private let logger: OSLog
    private var readyState: ReadyState = .raw

    private var lastEventId: String?
    private var reconnectTime: TimeInterval
    private var connectedTime: Date?

    private var reconnectionAttempts: Int = 0
    private var errorHandlerAction: ConnectionErrorAction? = nil
    private let utf8LineParser: UTF8LineParser = UTF8LineParser()
    private var eventParser: EventParser!
    private var sessionTask: URLSessionTask?

    public init(config: Config) {
        self.config = config
        self.lastEventId = config.lastEventId
        self.reconnectTime = config.reconnectTime
        self.logger = OSLog(subsystem: "com.launchdarkly.swift-eventsource", category: "LDEventSource")
    }

    public func start() {
        delegateQueue.async {
            guard self.readyState == .raw
            else {
                os_log("Start method called on this already-started EventSource object. Doing nothing", log: self.logger, type: .info)
                return
            }
            self.connect()
        }
    }

    public func stop() {
        sessionTask?.cancel()
        if (readyState == .open) {
            config.handler.onClosed()
        }
        readyState = .shutdown
    }

    public func getLastEventId() -> String? { lastEventId }

    private func connect() {
        os_log("Starting EventSource client", log: logger, type: .info)
        let connectionHandler: ConnectionHandler = (
            setReconnectionTime: { reconnectionTime in self.reconnectTime = reconnectionTime },
            setLastEventId: { eventId in self.lastEventId = eventId }
        )
        self.eventParser = EventParser(handler: self.config.handler, connectionHandler: connectionHandler)
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.httpAdditionalHeaders = ["Accept": "text/event-stream", "Cache-Control": "no-cache"]
        sessionConfig.timeoutIntervalForRequest = self.config.idleTimeout
        let session = URLSession.init(configuration: sessionConfig, delegate: self, delegateQueue: nil)
        var urlRequest = URLRequest(url: self.config.url,
                                    cachePolicy: URLRequest.CachePolicy.reloadIgnoringLocalAndRemoteCacheData,
                                    timeoutInterval: self.config.idleTimeout)
        urlRequest.httpMethod = self.config.method
        urlRequest.httpBody = self.config.body
        urlRequest.setValue(self.lastEventId, forHTTPHeaderField: "Last-Event-ID")
        urlRequest.allHTTPHeaderFields?.merge(self.config.headers, uniquingKeysWith: { $1 })
        let task = session.dataTask(with: urlRequest)
        task.resume()
        sessionTask = task
    }

    private func dispatchError(error: Error) -> ConnectionErrorAction {
        let action: ConnectionErrorAction = config.connectionErrorHandler(error)
        if action != .shutdown {
            config.handler.onError(error: error)
        }
        return action
    }

    private func afterComplete() {
        var nextState: ReadyState = .closed
        let currentState: ReadyState = readyState
        if errorHandlerAction == .shutdown {
            os_log("Connection has been explicitly shut down by error handler", log: logger, type: .info)
            nextState = .shutdown
        }
        readyState = nextState
        os_log("State: %@ -> %@", log: logger, type: .debug, currentState.rawValue, nextState.rawValue)

        if currentState == .open {
            config.handler.onClosed()
        }

        if nextState != .shutdown {
            reconnect()
        }
    }

    private func reconnect() {
        reconnectionAttempts += 1

        if let connectedTime = connectedTime, Date().timeIntervalSince(connectedTime) >= config.backoffResetThreshold {
            reconnectionAttempts = 0
        }

        let maxSleep = min(config.maxReconnectTime, reconnectTime * pow(2.0, Double(reconnectionAttempts)))
        let sleep = maxSleep / 2 + Double.random(in: 0...(maxSleep/2))

        os_log("Waiting %.3f seconds before reconnecting...", log: logger, type: .info, sleep)
        delegateQueue.asyncAfter(deadline: .now() + sleep) {
            self.connect()
        }
    }

    // Tells the delegate that the task finished transferring data.
    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didCompleteWithError error: Error?) {
        utf8LineParser.closeAndReset().forEach(eventParser.parse)
        // Send additional empty line to force a last dispatch
        eventParser.parse(line: "")

        if let error = error {
            if readyState != .shutdown {
                os_log("Connection error: %@", log: logger, type: .info, error.localizedDescription)
                errorHandlerAction = dispatchError(error: error)
            } else {
                errorHandlerAction = .shutdown
            }
        } else {
            os_log("Connection unexpectedly closed.", log: logger, type: .info)
        }

        afterComplete()
    }

    // Tells the delegate that the data task received the initial reply (headers) from the server.
    public func urlSession(_ session: URLSession,
                           dataTask: URLSessionDataTask,
                           didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        os_log("initial reply received", log: logger, type: .debug)

        let httpResponse = response as! HTTPURLResponse
        if (200..<300).contains(httpResponse.statusCode) {
            connectedTime = Date()
            readyState = .open
            config.handler.onOpened()
            completionHandler(.allow)
        } else {
            os_log("Unsuccessful response: %d", log: logger, type: .info, httpResponse.statusCode)
            errorHandlerAction = dispatchError(error: UnsuccessfulResponseError(responseCode: httpResponse.statusCode))
            completionHandler(.cancel)
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        utf8LineParser.append(data).forEach(eventParser.parse)
    }

    /// Struct describing the configuration of the EventSource
    public struct Config {
        public let handler: EventHandler
        public let url: URL

        /// The method to use for the EventSource connection
        public var method: String = "GET"
        /// Optional body to be sent with the initial request
        public var body: Data? = nil
        /// Error handler that can determine whether to proceed or shutdown.
        public var connectionErrorHandler: ConnectionErrorHandler = { _ in .proceed }
        /// An initial value for the last-event-id to be set on the initial request
        public var lastEventId: String? = nil
        /// Additional headers to be set on the request
        public var headers: [String: String] = [:]
        /// The minimum amount of time to wait before reconnecting after a failure
        public var reconnectTime: TimeInterval = 1.0
        /// The maximum amount of time to wait before reconnecting after a failure
        public var maxReconnectTime: TimeInterval = 30.0
        /// The minimum amount of time for an EventSource connection to remain open before allowing connection
        /// backoff to reset.
        public var backoffResetThreshold: TimeInterval = 60.0
        /// The maximum amount of time between receiving any data before considering the connection to have
        /// timed out.
        public var idleTimeout: TimeInterval = 300.0

        /// Create a new configuration with an EventHandler and a URL
        public init(handler: EventHandler, url: URL) {
            self.handler = handler
            self.url = url
        }
    }
}
