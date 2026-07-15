import Foundation
import Logging

#if os(Linux) || os(Windows)
import FoundationNetworking
#endif

/**
 Provides an EventSource client for consuming Server-Sent Events.

 See the [Server-Sent Events spec](https://html.spec.whatwg.org/multipage/server-sent-events.html) for more details.
 */
public final class EventSource: Sendable {
    private let esDelegate: EventSourceDelegate
    private let stream: AsyncStream<EventSourceEvent>

    /**
     The stream of events produced by this `EventSource`.

     Call `start()` to open the connection; received events and state changes are then delivered here as
     `EventSourceEvent` values. The sequence terminates when `stop()` is called, when the consuming task is
     cancelled, or after an unrecoverable `.error` (refer to `EventSourceError.recoverable`).

     - Important:
        This is a **single-consumer** sequence: iterate it from exactly one task. Iterating it more than once
        splits events between the iterators rather than delivering each event to all of them.

     - Important:
        The stream is **unbounded** and applies no backpressure to the network. The consumer is expected to drain
        it continuously; events parsed off the connection are buffered until iterated, so a consumer that pauses,
        falls behind, or never iterates while the connection is open will accumulate events in memory without
        bound. This mirrors `AsyncStream`'s default buffering and the behavior of LaunchDarkly's other
        async-pull SSE clients; the intended consumers (an SDK's data source) process each event synchronously and
        never fall behind.
     */
    public var events: AsyncStream<EventSourceEvent> { stream }

    /**
     Initialize the `EventSource` client with the given configuration.

     - Parameter config: The configuration for initializing the `EventSource` client.
     */
    public init(config: Config) {
        // `.unbounded` (the default) is deliberate: dropping events would corrupt last-event-id resumption, and the
        // URLSessionDataDelegate data path cannot apply real backpressure to the socket. The consumer-must-drain
        // contract is documented on `events`.
        let (stream, continuation) = AsyncStream.makeStream(of: EventSourceEvent.self)
        self.stream = stream
        let delegate = EventSourceDelegate(config: config, continuation: continuation)
        self.esDelegate = delegate
        // If the consumer stops iterating (its task is cancelled or the stream is dropped) without calling stop(),
        // tear the connection down. Captured weakly so the continuation does not retain the delegate (and so this
        // EventSource); if the delegate is already gone there is nothing left to tear down.
        continuation.onTermination = { [weak delegate] _ in delegate?.stop() }
    }

    /// Tears the connection down if this `EventSource` is deallocated without `stop()` having been called -- e.g. a
    /// caller that creates one, never iterates `events`, and drops it. Idempotent with `stop()`.
    deinit {
        esDelegate.stop()
    }

    /**
     Start the `EventSource` client.

     This will initiate a streaming connection to the configured URL. Received events and state changes are
     delivered through the `events` sequence.
     */
    public func start() {
        esDelegate.start()
    }

    /// Shuts down the `EventSource` client and finishes the `events` stream. It is not valid to restart the client
    /// after calling this function.
    public func stop() {
        esDelegate.stop()
    }

    /// Get the most recently received event ID, or the value of `EventSource.Config.lastEventId` if no event IDs have
    /// been received.
    public func getLastEventId() -> String? { esDelegate.getLastEventId() }

    /// Struct for configuring the EventSource.
    public struct Config {
        /// The `URL` of the request used when connecting to the EventSource API.
        public let url: URL

        /// The HTTP method to use for the API request.
        public var method: String = "GET"
        /// Optional HTTP body to be included in the API request.
        public var body: Data?
        /// Additional HTTP headers to be set on the request
        public var headers: [String: String] = [:]
        /// Transform function to allow dynamically configuring the headers on each API request.
        public var headerTransform: HeaderTransform = { $0 }
        /// An initial value for the last-event-id header to be sent on the initial request
        public var lastEventId: String = ""

        /// The `swift-log` logger that will be used. Defaults to a logger backed
        /// by a no-op handler that discards all output; assign a `Logging.Logger`
        /// to receive log messages.
        public var logger: Logging.Logger = Logger(
            label: "com.launchdarkly.swift-eventsource",
            factory: { _ in SwiftLogNoOpLogHandler() }
        )

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

                #if !os(Linux) && !os(Windows)
                sessionConfig.tlsMinimumSupportedProtocolVersion = .TLSv12
                #endif
                return sessionConfig
            }
            set {
                // swiftlint:disable:next force_cast
                _urlSessionConfiguration = newValue.copy() as! URLSessionConfiguration
            }
        }

        /// Create a new configuration with the `URL` to connect to.
        public init(url: URL) {
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
// All mutable state is confined to the serial `delegateQueue` (the URLSession
// delegate callbacks are dispatched onto it as well), which provides the
// synchronization the compiler cannot verify -- hence `@unchecked Sendable`.
final class EventSourceDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let delegateQueue: DispatchQueue = DispatchQueue(label: "ESDelegateQueue")

    private let logger: Logging.Logger

    private let config: EventSource.Config
    private let handler: EventHandler
    private let continuation: AsyncStream<EventSourceEvent>.Continuation

    private var readyState: ReadyState = .raw {
        didSet {
            logger.debug("State: \(oldValue.rawValue) -> \(readyState.rawValue)")
        }
    }

    private let utf8LineParser: UTF8LineParser = UTF8LineParser()
    private let eventParser: EventParser
    private let reconnectionTimer: ReconnectionTimer
    private var urlSession: URLSession?
    private var sessionTask: URLSessionDataTask?

    init(config: EventSource.Config, continuation: AsyncStream<EventSourceEvent>.Continuation) {
        self.config = config
        self.logger = config.logger
        self.continuation = continuation

        let handler = ContinuationEventHandler(continuation: continuation)
        self.handler = handler
        self.eventParser = EventParser(handler: handler,
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
                self.logger.info("start() called on already-started EventSource object. Returning")
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
                self.handler.onClosed()
            }
            self.urlSession?.invalidateAndCancel()
            self.urlSession = nil
            self.continuation.finish()
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
        // A reconnect can be scheduled (via asyncAfter) before stop() runs; once shut down, do not reopen.
        guard readyState != .shutdown
        else { return }
        logger.info("Starting EventSource client")
        let task = urlSession?.dataTask(with: createRequest())
        task?.resume()
        sessionTask = task
    }

    /// HTTP statuses the client retries on its own. Mirrors the classification shared with the other
    /// LaunchDarkly SSE clients: 5xx, 400, 408, and 429 are recoverable; everything else is terminal.
    static func isRecoverable(statusCode: Int) -> Bool {
        (500..<600).contains(statusCode) || statusCode == 400 || statusCode == 408 || statusCode == 429
    }

    /// Flattens an `HTTPURLResponse`'s headers into a `[String: String]` with lowercased keys, so callers can
    /// look up directive headers (e.g. `x-ld-envid`, `x-ld-fd-fallback`) without worrying about server casing.
    static func headerFields(from response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String, let value = value as? String {
                headers[key.lowercased()] = value
            }
        }
        return headers
    }

    /// Classifies a connection failure, reports it on the stream, and returns whether the client should retry.
    /// An HTTP response is recoverable per `isRecoverable(statusCode:)`; a transport error (no status) defaults to
    /// recoverable. `underlyingError` carries the transport error for the no-status case (nil for HTTP responses).
    func emitError(statusCode: Int?, headers: [String: String], underlyingError: (any Error)?) -> Bool {
        let recoverable = statusCode.map(EventSourceDelegate.isRecoverable) ?? true
        handler.onError(EventSourceError(
            statusCode: statusCode,
            headers: headers,
            recoverable: recoverable,
            underlyingError: underlyingError
        ))
        return recoverable
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
                logger.info("Connection error: \(error.localizedDescription)")
                // Transport errors carry no HTTP status, so they are always recoverable.
                if !emitError(statusCode: nil, headers: [:], underlyingError: error) {
                    logger.info("Connection has been shut down: error reported as unrecoverable")
                    if readyState == .open {
                        handler.onClosed()
                    }
                    readyState = .shutdown
                    continuation.finish()
                    return
                }
            }
        } else if readyState != .open {
            // The task completed with no error, but the stream never opened -- no usable HTTP response
            // was delivered. On Linux, libcurl terminates a 3xx redirect with an empty or missing
            // Location exactly this way (no error, no response, no willPerformHTTPRedirection call),
            // whereas CFNetwork surfaces it as an error. Retrying the same URL just repeats it, so
            // report an unrecoverable error and stop instead of reconnecting forever.
            logger.info("Connection closed before any response was received; reporting as unrecoverable")
            handler.onError(EventSourceError(statusCode: nil, headers: [:], recoverable: false, underlyingError: nil))
            readyState = .shutdown
            continuation.finish()
            return
        } else {
            logger.info("Connection unexpectedly closed.")
        }

        if readyState == .open {
            handler.onClosed()
        }

        readyState = .closed
        let sleep = reconnectionTimer.reconnectDelay(baseDelay: currentRetry)
        logger.info("Waiting \(String(format: "%.3f", sleep)) seconds before reconnecting...")
        delegateQueue.asyncAfter(deadline: .now() + sleep) { [weak self] in
            self?.connect()
        }
    }

    // Tells the delegate that the data task received the initial reply (headers) from the server.
    public func urlSession(_ session: URLSession,
                           dataTask: URLSessionDataTask,
                           didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        logger.debug("Initial reply received")

        guard readyState != .shutdown
        else {
            completionHandler(.cancel)
            return
        }

        // swiftlint:disable:next force_cast
        let httpResponse = response as! HTTPURLResponse
        let statusCode = httpResponse.statusCode
        let headers = EventSourceDelegate.headerFields(from: httpResponse)
        if (200..<300).contains(statusCode) && statusCode != 204 {
            reconnectionTimer.connectedTime = Date()
            readyState = .open
            handler.onOpened(headers: headers)
            completionHandler(.allow)
        } else {
            logger.info("Unsuccessful response: \(statusCode)")
            // The error (with status, headers, and recoverable flag) is reported on the stream either way.
            // An unrecoverable status ends the stream; a recoverable one is left to the reconnect path
            // (the cancelled task completes through didCompleteWithError, which schedules the retry).
            if !emitError(statusCode: statusCode, headers: headers, underlyingError: nil) {
                logger.info("Connection has been shut down: status \(statusCode) reported as unrecoverable")
                readyState = .shutdown
                continuation.finish()
            }
            completionHandler(.cancel)
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        utf8LineParser.append(data).forEach(eventParser.parse)
    }
}

// MARK: ContinuationEventHandler
// Internal adapter that forwards the delegate's and EventParser's callbacks into the public
// `EventSource.events` stream.
final class ContinuationEventHandler: EventHandler {
    private let continuation: AsyncStream<EventSourceEvent>.Continuation

    init(continuation: AsyncStream<EventSourceEvent>.Continuation) {
        self.continuation = continuation
    }

    func onOpened(headers: [String: String]) { continuation.yield(.opened(headers: headers)) }
    func onClosed() { continuation.yield(.closed) }
    func onMessage(eventType: String, messageEvent: MessageEvent) {
        continuation.yield(.message(eventType: eventType, messageEvent))
    }
    func onComment(comment: String) { continuation.yield(.comment(comment)) }
    func onError(_ error: EventSourceError) { continuation.yield(.error(error)) }
}
