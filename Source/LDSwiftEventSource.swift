import Foundation

#if os(Linux)
import FoundationNetworking
#endif

#if !os(Linux)
import os.log
#endif

public class EventSource {
    private let esDelegate: EventSourceDelegate

    /**
     Initialize an EventSource with the given configuration.

     - Parameter config: The configuration for initializing the EventSource.
     */
    public init(config: Config) {
        esDelegate = EventSourceDelegate(config: config)
    }

    /**
     Start the EventSource object.

     This will create a stream connection to the configured URL. The application will be informed of received events
     and state changes using the configured EventHandler.
     */
    public func start() {
        esDelegate.start()
    }

    /// Shuts down the EventSource object. It is not valid to restart the EventSource after calling this function.
    public func stop() {
        esDelegate.stop()
    }

    /**
     Get the most recently received event ID, or the configured `lastEventId` if no event IDs have been received.
     */
    public func getLastEventId() -> String? { esDelegate.getLastEventId() }

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
        /// Provides the ability to add conditional headers
        public var headerTransform: HeaderTransform = { $0 }
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

class EventSourceDelegate: NSObject, URLSessionDataDelegate {

    #if !os(Linux)
    private let logger: OSLog = OSLog(subsystem: "com.launchdarkly.swift-eventsource", category: "LDEventSource")
    #endif

    private let config: EventSource.Config

    private let delegateQueue: DispatchQueue = DispatchQueue(label: "ESDelegateQueue")

    private var readyState: ReadyState = .raw

    private var lastEventId: String?
    private var reconnectTime: TimeInterval
    private var connectedTime: Date?

    private var reconnectionAttempts: Int = 0
    private var errorHandlerAction: ConnectionErrorAction? = nil
    private let utf8LineParser: UTF8LineParser = UTF8LineParser()
    private var eventParser: EventParser!
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
                os_log("Start method called on this already-started EventSource object. Doing nothing", log: self.logger, type: .info)
                #endif
                return
            }
            self.connect()
        }
    }

    func stop() {
        sessionTask?.cancel()
        if readyState == .open {
            config.handler.onClosed()
        }
        readyState = .shutdown
    }

    func getLastEventId() -> String? { lastEventId }

    private func connect() {
        #if !os(Linux)
        os_log("Starting EventSource client", log: logger, type: .info)
        #endif
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
        urlRequest.allHTTPHeaderFields = self.config.headerTransform(
            urlRequest.allHTTPHeaderFields?.merging(self.config.headers) { $1 } ?? self.config.headers
        )
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
            #if !os(Linux)
            os_log("Connection has been explicitly shut down by error handler", log: logger, type: .info)
            #endif
            nextState = .shutdown
        }
        readyState = nextState
        #if !os(Linux)
        os_log("State: %@ -> %@", log: logger, type: .debug, currentState.rawValue, nextState.rawValue)
        #endif

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

        #if !os(Linux)
        os_log("Waiting %.3f seconds before reconnecting...", log: logger, type: .info, sleep)
        #endif
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
