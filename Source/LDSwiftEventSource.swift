import Foundation

#if os(Linux)
import FoundationNetworking
#endif

#if !os(Linux)
import os.log
#endif

/**
 Provides an EventSource client for consuming Server-Sent Events.

 See the [Server-Sent Events spec](https://html.spec.whatwg.org/multipage/server-sent-events.html) for more details.
 */
public class EventSource {
    private let esDelegate: EventSourceDelegate

    /**
     Initialize the `EventSource` client with the given configuration.

     - Parameter config: The configuration for initializing the `EventSource` client.
     */
    public init(config: Config) {
        esDelegate = EventSourceDelegate(config: config)
    }

    /**
     Start the `EventSource` client.

     This will initiate a streaming connection to the configured URL. The application will be informed of received
     events and state changes using the configured `EventHandler`.
     */
    public func start() {
        esDelegate.start()
    }

    /// Shuts down the `EventSource` client. It is not valid to restart the client after calling this function.
    public func stop() {
        esDelegate.stop()
    }

    /// Get the most recently received event ID, or the value of `EventSource.Config.lastEventId` if no event IDs have
    /// been received.
    public func getLastEventId() -> String? { esDelegate.getLastEventId() }

    /// Struct for configuring the EventSource.
    public struct Config {
        /// The `EventHandler` called in response to activity on the stream.
        public let handler: EventHandler
        /// The `URL` of the request used when connecting to the EventSource API.
        public let url: URL

        /// The HTTP method to use for the API request.
        public var method: String = "GET"
        /// Optional HTTP body to be included in the API request.
        public var body: Data?
        /// An initial value for the last-event-id header to be sent on the initial request
        public var lastEventId: String?
        /// Additional HTTP headers to be set on the request
        public var headers: [String: String] = [:]
        /// Transform function to allow dynamically configuring the headers on each API request.
        public var headerTransform: HeaderTransform = { $0 }
        /// The minimum amount of time to wait before reconnecting after a failure
        public var reconnectTime: TimeInterval = 1.0
        /// The maximum amount of time to wait before reconnecting after a failure
        public var maxReconnectTime: TimeInterval = 30.0
        /// The minimum amount of time for an `EventSource` connection to remain open before allowing the connection
        /// backoff to reset.
        public var backoffResetThreshold: TimeInterval = 60.0
        /// The maximum amount of time between receiving any data before considering the connection to have timed out.
        public var idleTimeout: TimeInterval = 300.0

        /**
         An error handler that is called when an error occurs and can shut down the client in response.

         The default error handler will always attempt to reconnect on an error, unless `EventSource.stop()` is called.
         */
        public var connectionErrorHandler: ConnectionErrorHandler = { _ in .proceed }

        /// Create a new configuration with an `EventHandler` and a `URL`
        public init(handler: EventHandler, url: URL) {
            self.handler = handler
            self.url = url
        }
    }
}

class EventSourceDelegate: NSObject, URLSessionDataDelegate {
    #if !os(Linux)
    private let logger: OSLog = OSLog(subsystem: "com.launchdarkly.swift-eventsource", category: "LDEventSource")
    #endif

    private let config: EventSource.Config

    private let delegateQueue: DispatchQueue = DispatchQueue(label: "ESDelegateQueue")

    private var readyState: ReadyState = .raw {
        didSet {
            #if !os(Linux)
            os_log("State: %@ -> %@", log: logger, type: .debug, oldValue.rawValue, readyState.rawValue)
            #endif
        }
    }

    private var lastEventId: String?
    private var reconnectTime: TimeInterval
    private var connectedTime: Date?

    private var reconnectionAttempts: Int = 0
    private var errorHandlerAction: ConnectionErrorAction = .proceed
    private let utf8LineParser: UTF8LineParser = UTF8LineParser()
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var eventParser: EventParser!
    private var urlSession: URLSession?
    private var sessionTask: URLSessionDataTask?

    init(config: EventSource.Config) {
        self.config = config
        self.lastEventId = config.lastEventId
        self.reconnectTime = config.reconnectTime
    }

    func start() {
        delegateQueue.async {
            guard self.readyState == .raw
            else {
                #if !os(Linux)
                os_log("start() called on already-started EventSource object. Returning", log: self.logger, type: .info)
                #endif
                return
            }
            self.urlSession = self.createSession()
            self.connect()
        }
    }

    func stop() {
        let previousState = readyState
        readyState = .shutdown
        sessionTask?.cancel()
        if previousState == .open {
            config.handler.onClosed()
        }
    }

    func getLastEventId() -> String? { lastEventId }

    func createSession() -> URLSession {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.httpAdditionalHeaders = ["Accept": "text/event-stream", "Cache-Control": "no-cache"]
        sessionConfig.timeoutIntervalForRequest = self.config.idleTimeout
        return URLSession(configuration: sessionConfig, delegate: self, delegateQueue: nil)
    }

    func createRequest() -> URLRequest {
        var urlRequest = URLRequest(url: self.config.url,
                                    cachePolicy: URLRequest.CachePolicy.reloadIgnoringLocalAndRemoteCacheData,
                                    timeoutInterval: self.config.idleTimeout)
        urlRequest.httpMethod = self.config.method
        urlRequest.httpBody = self.config.body
        urlRequest.setValue(self.lastEventId, forHTTPHeaderField: "Last-Event-ID")
        urlRequest.allHTTPHeaderFields = self.config.headerTransform(
            urlRequest.allHTTPHeaderFields?.merging(self.config.headers) { $1 } ?? self.config.headers
        )
        return urlRequest
    }

    private func connect() {
        #if !os(Linux)
        os_log("Starting EventSource client", log: logger, type: .info)
        #endif
        let connectionHandler: ConnectionHandler = (
            setReconnectionTime: { reconnectionTime in self.reconnectTime = reconnectionTime },
            setLastEventId: { eventId in self.lastEventId = eventId }
        )
        self.eventParser = EventParser(handler: self.config.handler, connectionHandler: connectionHandler)
        let task = urlSession?.dataTask(with: createRequest())
        task?.resume()
        sessionTask = task
    }

    func dispatchError(error: Error) -> ConnectionErrorAction {
        let action: ConnectionErrorAction = config.connectionErrorHandler(error)
        if action != .shutdown {
            config.handler.onError(error: error)
        }
        return action
    }

    private func afterComplete() {
        guard readyState != .shutdown
        else { return }

        var nextState: ReadyState = .closed
        let currentState: ReadyState = readyState
        if errorHandlerAction == .shutdown {
            #if !os(Linux)
            os_log("Connection has been explicitly shut down by error handler", log: logger, type: .info)
            #endif
            nextState = .shutdown
        }
        readyState = nextState

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
        self.connectedTime = nil

        let maxSleep = min(config.maxReconnectTime, reconnectTime * pow(2.0, Double(reconnectionAttempts)))
        let sleep = maxSleep / 2 + Double.random(in: 0...(maxSleep / 2))

        #if !os(Linux)
        os_log("Waiting %.3f seconds before reconnecting...", log: logger, type: .info, sleep)
        #endif
        delegateQueue.asyncAfter(deadline: .now() + sleep) {
            self.connect()
        }
    }

    // MARK: URLSession Delegates

    // Tells the delegate that the task finished transferring data.
    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didCompleteWithError error: Error?) {
        utf8LineParser.closeAndReset().forEach(eventParser.parse)
        // Send additional empty line to force a last dispatch
        eventParser.parse(line: "")

        if let error = error {
            if readyState != .shutdown && errorHandlerAction != .shutdown {
                #if !os(Linux)
                os_log("Connection error: %@", log: logger, type: .info, error.localizedDescription)
                #endif
                errorHandlerAction = dispatchError(error: error)
            } else {
                errorHandlerAction = .shutdown
            }
        } else {
            #if !os(Linux)
            os_log("Connection unexpectedly closed.", log: logger, type: .info)
            #endif
        }

        afterComplete()
    }

    // Tells the delegate that the data task received the initial reply (headers) from the server.
    public func urlSession(_ session: URLSession,
                           dataTask: URLSessionDataTask,
                           didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        #if !os(Linux)
        os_log("initial reply received", log: logger, type: .debug)
        #endif

        guard readyState != .shutdown
        else {
            completionHandler(.cancel)
            return
        }

        // swiftlint:disable:next force_cast
        let httpResponse = response as! HTTPURLResponse
        if (200..<300).contains(httpResponse.statusCode) {
            connectedTime = Date()
            readyState = .open
            config.handler.onOpened()
            completionHandler(.allow)
        } else {
            #if !os(Linux)
            os_log("Unsuccessful response: %d", log: logger, type: .info, httpResponse.statusCode)
            #endif
            errorHandlerAction = dispatchError(error: UnsuccessfulResponseError(responseCode: httpResponse.statusCode))
            completionHandler(.cancel)
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        utf8LineParser.append(data).forEach(eventParser.parse)
    }
}
