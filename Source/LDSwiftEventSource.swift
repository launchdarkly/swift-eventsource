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
        public var lastEventId: String = ""
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

class ReconnectionTimer {
    private let maxDelay: TimeInterval
    private let resetInterval: TimeInterval

    var backoffCount: Int = 0
    var connectedTime: Date?

    init(maxDelay: TimeInterval, resetInterval: TimeInterval) {
        self.maxDelay = maxDelay
        self.resetInterval = resetInterval
    }

    func reconnectDelay(baseDelay: TimeInterval) -> TimeInterval {
        backoffCount += 1
        if let connectedTime = connectedTime, Date().timeIntervalSince(connectedTime) >= resetInterval {
            backoffCount = 0
        }
        self.connectedTime = nil
        let maxSleep = min(maxDelay, baseDelay * pow(2.0, Double(backoffCount)))
        return maxSleep / 2 + Double.random(in: 0...(maxSleep / 2))
    }
}

// MARK: EventSourceDelegate
class EventSourceDelegate: NSObject, URLSessionDataDelegate {
    private let delegateQueue: DispatchQueue = DispatchQueue(label: "ESDelegateQueue")
    private let logger = Logs()

    private let config: EventSource.Config

    private var readyState: ReadyState = .raw {
        didSet {
            logger.log(.debug, "State: %@ -> %@", oldValue.rawValue, readyState.rawValue)
        }
    }

    private let utf8LineParser: UTF8LineParser = UTF8LineParser()
    private let eventParser: EventParser
    private let reconnectionTimer: ReconnectionTimer
    private var urlSession: URLSession?
    private var sessionTask: URLSessionDataTask?

    init(config: EventSource.Config) {
        self.config = config
        self.eventParser = EventParser(handler: config.handler,
                                       initialEventId: config.lastEventId,
                                       initialRetry: config.reconnectTime)
        self.reconnectionTimer = ReconnectionTimer(maxDelay: config.maxReconnectTime,
                                                   resetInterval: config.backoffResetThreshold)
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
            self.readyState = .connecting
            self.urlSession = self.createSession()
            self.connect()
        }
    }

    func stop() {
        delegateQueue.async {
            let previousState = self.readyState
            self.readyState = .shutdown
            self.sessionTask?.cancel()
            if previousState == .open {
                self.config.handler.onClosed()
            }
            self.urlSession?.invalidateAndCancel()
            self.urlSession = nil
        }
    }

    func getLastEventId() -> String { eventParser.getLastEventId() }

    func createSession() -> URLSession {
        let opQueue = OperationQueue()
        opQueue.underlyingQueue = self.delegateQueue
        return URLSession(configuration: config.urlSessionConfiguration, delegate: self, delegateQueue: opQueue)
    }

    func createRequest() -> URLRequest {
        var urlRequest = URLRequest(url: self.config.url,
                                    cachePolicy: URLRequest.CachePolicy.reloadIgnoringLocalAndRemoteCacheData,
                                    timeoutInterval: self.config.idleTimeout)
        urlRequest.httpMethod = self.config.method
        urlRequest.httpBody = self.config.body
        if !eventParser.getLastEventId().isEmpty {
            urlRequest.setValue(eventParser.getLastEventId(), forHTTPHeaderField: "Last-Event-Id")
        }
        urlRequest.allHTTPHeaderFields = self.config.headerTransform(
            urlRequest.allHTTPHeaderFields?.merging(self.config.headers) { $1 } ?? self.config.headers
        )
        return urlRequest
    }

    private func connect() {
        logger.log(.info, "Starting EventSource client")
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

    // MARK: URLSession Delegates

    // Tells the delegate that the task finished transferring data.
    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didCompleteWithError error: Error?) {
        utf8LineParser.closeAndReset()
        let currentRetry = eventParser.reset()

        guard readyState != .shutdown
        else { return }

        if let error = error {
            if (error as NSError).code != NSURLErrorCancelled {
                logger.log(.info, "Connection error: %@", error.localizedDescription)
                if dispatchError(error: error) == .shutdown {
                    logger.log(.info, "Connection has been explicitly shut down by error handler")
                    if readyState == .open {
                        config.handler.onClosed()
                    }
                    readyState = .shutdown
                    return
                }
            }
        } else {
            logger.log(.info, "Connection unexpectedly closed.")
        }

        if readyState == .open {
            config.handler.onClosed()
        }

        readyState = .closed
        let sleep = reconnectionTimer.reconnectDelay(baseDelay: currentRetry)
        logger.log(.info, "Waiting %.3f seconds before reconnecting...", sleep)
        delegateQueue.asyncAfter(deadline: .now() + sleep) { [weak self] in
            self?.connect()
        }
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
            reconnectionTimer.connectedTime = Date()
            readyState = .open
            config.handler.onOpened()
            completionHandler(.allow)
        } else {
            logger.log(.info, "Unsuccessful response: %d", httpResponse.statusCode)
            if dispatchError(error: UnsuccessfulResponseError(responseCode: httpResponse.statusCode)) == .shutdown {
                logger.log(.info, "Connection has been explicitly shut down by error handler")
                readyState = .shutdown
            }
            completionHandler(.cancel)
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        utf8LineParser.append(data).forEach(eventParser.parse)
    }
}
