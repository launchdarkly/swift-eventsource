import Foundation

public protocol EventHandler {
    func onOpened()
    func onClosed()
    func onMessage(event: String, messageEvent: MessageEvent)
    func onComment(comment: String)
    func onError(error: Error)
}

typealias ConnectionHandler = (setReconnectionTime: (TimeInterval) -> (), setLastEventId: (String) -> ())
public typealias ConnectionErrorHandler = (Error) -> ConnectionErrorAction

///
public enum ConnectionErrorAction {
    /// Specifies that the error should be logged normally and dispatched to the EventHandler. Connection retrying will proceed normally if appropriate.
    case proceed
    /// Specifies that the connection should be immediately shut down and not retried. The error will not be dispatched to the EventHandler
    case shutdown
}

/// Enum values representing the states of an EventSource
enum ReadyState {
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

public struct MessageEvent: Equatable, Hashable {
    let data: String
    let lastEventId: String?

    init(data: String, lastEventId: String? = nil) {
        self.data = data
        self.lastEventId = lastEventId
    }
}

public class EventSource: NSObject, URLSessionDataDelegate {

    private let config: Config

    private let delegateQueue: DispatchQueue = DispatchQueue(label: "ESDelegateQueue")
    private var readyState: ReadyState = .raw

    private var lastEventId: String?
    private var reconnectTime: TimeInterval
    private var connectedTime: Date?

    private var reconnectionAttempts: Int = 0
    private var errorHandlerAction: ConnectionErrorAction? = nil
    private let utf8LineParser: UTF8LineParser = UTF8LineParser()
    private var eventParser: EventParser!

    public init(config: Config) {
        self.config = config
        self.lastEventId = config.lastEventId
        self.reconnectTime = config.reconnectTime
    }

    private func log(_ msg: String) {
        NSLog("%@", "LDSwiftEventSource: \(msg)")
    }

    public func start() {
        delegateQueue.async {
            guard self.readyState == .raw
            else {
                self.log("Start method called on this already-started EventSource object. Doing nothing")
                return
            }
            self.connect()
        }
    }

    private func connect() {
        self.log("Starting EventSource client")
        let connectionHandler: ConnectionHandler = (
            setReconnectionTime: { reconnectionTime in self.reconnectTime = reconnectionTime },
            setLastEventId: { eventId in self.lastEventId = eventId }
        )
        self.eventParser = EventParser(handler: self.config.handler, connectionHandler: connectionHandler)
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.httpAdditionalHeaders = ["Accept": "text/event-stream", "Cache-Control": "no-cache"]
        sessionConfig.timeoutIntervalForRequest = self.config.idleTimeout
        // TODO change queue
        let session = URLSession.init(configuration: sessionConfig, delegate: self, delegateQueue: nil)
        var urlRequest = URLRequest(url: self.config.url, cachePolicy: URLRequest.CachePolicy.reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: self.config.idleTimeout)
        urlRequest.httpMethod = self.config.method
        urlRequest.httpBody = self.config.body
        urlRequest.setValue(self.lastEventId, forHTTPHeaderField: "Last-Event-ID")
        urlRequest.allHTTPHeaderFields?.merge(self.config.headers, uniquingKeysWith: { $1 })
        session.dataTask(with: urlRequest).resume()
    }

    private func dispatchError(error: Error) -> ConnectionErrorAction {
        let action: ConnectionErrorAction = config.connectionErrorHandler(error)
        if action != .shutdown {
            config.handler.onError(error: error)
        }
        return action
    }

    func getLastEventId() -> String? { lastEventId }

    private func afterComplete() {
        var nextState: ReadyState = .closed
        let currentState: ReadyState = readyState
        if errorHandlerAction == .shutdown {
            log("Connection has been explicitly shut down by error handler")
            nextState = .shutdown
        }
        readyState = nextState
        log("State: \(currentState) -> \(nextState)")

        if currentState == .open {
            config.handler.onClosed()
        }

        if nextState != .shutdown {
            reconnect()
        }
    }

    private func reconnect() {
        if let connectedTime = connectedTime, Date().timeIntervalSince(connectedTime) >= config.backoffResetThreshold {
            reconnectionAttempts = 0
        }

        let maxSleep = min(config.maxReconnectTime, reconnectTime * pow(2.0, Double(reconnectionAttempts)))
        let sleep = maxSleep / 2 + Double.random(in: 0...maxSleep)

        log("Waiting \(sleep) seconds before reconnecting...")
        delegateQueue.asyncAfter(deadline: .now() + sleep) {
            self.connect()
        }
    }

    // MARK: URLSessionTaskDelegate methods

    // Tells the delegate that the task finished transferring data.
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        utf8LineParser.closeAndReset().forEach(eventParser.parse)
        // Send additional empty line to force a last dispatch
        eventParser.parse(line: "")

        if let error = error {
            if readyState != .shutdown {
                log("Connection error: \(error)")
                errorHandlerAction = dispatchError(error: error)
            } else {
                errorHandlerAction = .shutdown
            }
        } else {
            log("Connection unexpectedly closed.")
        }

        afterComplete()
    }

    // Tells the delegate that the remote server requested an HTTP redirect.
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        log("http redirect requested")
    }

    // Tells the delegate that the task is waiting until suitable connectivity is available before beginning the network load.
    public func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        log("task waiting")
    }

    // MARK: URLSessionDataDelegate methods

    // Tells the delegate that the data task received the initial reply (headers) from the server.
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        log("initial reply received")

        let httpResponse = response as! HTTPURLResponse
        log("reply \(httpResponse.statusCode)")

        if (200..<300).contains(httpResponse.statusCode) {
            connectedTime = Date()
            let lastState = readyState
            readyState = .open

            config.handler.onOpened()
        }

        completionHandler(.allow)
    }

    // Tells the delegate that the data task has received some of the expected data.
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        utf8LineParser.append(data).forEach(eventParser.parse)
    }

    public struct Config {
        public let handler: EventHandler
        public let url: URL

        public var method: String = "GET"
        public var body: Data? = nil
        public var connectionErrorHandler: ConnectionErrorHandler = { _ in .proceed }
        public var lastEventId: String? = nil
        public var headers: [String: String] = [:]
        public var reconnectTime: TimeInterval = 1.0
        public var maxReconnectTime: TimeInterval = 30.0
        public var backoffResetThreshold: TimeInterval = 60.0
        public var idleTimeout: TimeInterval = 300.0

        public init(handler: EventHandler, url: URL) {
            self.handler = handler
            self.url = url
        }
    }
}
