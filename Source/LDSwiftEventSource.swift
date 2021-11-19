import Foundation

#if os(Linux)
import FoundationNetworking
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

        private var _urlSessionConfiguration: URLSessionConfiguration = URLSessionConfiguration.default
        /**
         The `URLSessionConfiguration` used to create the `URLSession`.

         - Important:
            Note that this copies the given `URLSessionConfiguration` when set, and returns copies (updated with any
         overrides specified by other configuration options) when the value is retrieved. This prevents updating the
         `URLSessionConfiguration` after initializing `EventSource` with the `Config`, and prevents the `EventSource`
         from updating any properties of the given `URLSessionConfiguration`.

         - Since: 1.3.0
         */
        public var urlSessionConfiguration: URLSessionConfiguration {
            get {
                // swiftlint:disable:next force_cast
                let sessionConfig = _urlSessionConfiguration.copy() as! URLSessionConfiguration
                sessionConfig.httpAdditionalHeaders = ["Accept": "text/event-stream", "Cache-Control": "no-cache"]
                sessionConfig.timeoutIntervalForRequest = idleTimeout
                return sessionConfig
            }
            set {
                // swiftlint:disable:next force_cast
                _urlSessionConfiguration = newValue.copy() as! URLSessionConfiguration
            }
        }

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
    private let delegateQueue: DispatchQueue = DispatchQueue(label: "ESDelegateQueue")
    private let logger = Logs()

    private let config: EventSource.Config

    private var readyState: ReadyState = .raw {
        didSet {
            logger.log(.debug, "State: %@ -> %@", oldValue.rawValue, readyState.rawValue)
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
        delegateQueue.async { [weak self] in
            guard let self = self
            else { return }
            guard self.readyState == .raw
            else {
                self.logger.log(.info, "start() called on already-started EventSource object. Returning")
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
        urlSession?.invalidateAndCancel()
    }

    func getLastEventId() -> String? { lastEventId }

    func createSession() -> URLSession {
        URLSession(configuration: config.urlSessionConfiguration, delegate: self, delegateQueue: nil)
    }

    func createRequest() -> URLRequest {
        var urlRequest = URLRequest(url: self.config.url,
                                    cachePolicy: URLRequest.CachePolicy.reloadIgnoringLocalAndRemoteCacheData,
                                    timeoutInterval: self.config.idleTimeout)
        urlRequest.httpMethod = self.config.method
        urlRequest.httpBody = self.config.body
        urlRequest.setValue(self.lastEventId, forHTTPHeaderField: "Last-Event-Id")
        urlRequest.allHTTPHeaderFields = self.config.headerTransform(
            urlRequest.allHTTPHeaderFields?.merging(self.config.headers) { $1 } ?? self.config.headers
        )
        return urlRequest
    }

    private func connect() {
        logger.log(.info, "Starting EventSource client")
        let connectionHandler: ConnectionHandler = (
            setReconnectionTime: { [weak self] reconnectionTime in self?.reconnectTime = reconnectionTime },
            setLastEventId: { [weak self] eventId in self?.lastEventId = eventId }
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
            logger.log(.info, "Connection has been explicitly shut down by error handler")
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

        logger.log(.info, "Waiting %.3f seconds before reconnecting...", sleep)
        delegateQueue.asyncAfter(deadline: .now() + sleep) { [weak self] in
            self?.connect()
        }
    }

    // MARK: URLSession Delegates

    // Tells the delegate that the task finished transferring data.
    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didCompleteWithError error: Error?) {
        utf8LineParser.closeAndReset()
        eventParser.reset()

        if let error = error {
            // Ignore cancelled error
            if (error as NSError).code == NSURLErrorCancelled {
            } else if readyState != .shutdown && errorHandlerAction != .shutdown {
                logger.log(.info, "Connection error: %@", error.localizedDescription)
                errorHandlerAction = dispatchError(error: error)
            } else {
                errorHandlerAction = .shutdown
            }
        } else {
            logger.log(.info, "Connection unexpectedly closed.")
        }

        afterComplete()
    }

    // Tells the delegate that the data task received the initial reply (headers) from the server.
    public func urlSession(_ session: URLSession,
                           dataTask: URLSessionDataTask,
                           didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        logger.log(.debug, "Initial reply received")

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
            logger.log(.info, "Unsuccessful response: %d", httpResponse.statusCode)
            errorHandlerAction = dispatchError(error: UnsuccessfulResponseError(responseCode: httpResponse.statusCode))
            completionHandler(.cancel)
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        utf8LineParser.append(data).forEach(eventParser.parse)
    }
}
