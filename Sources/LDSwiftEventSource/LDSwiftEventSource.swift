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

class ESDelegate: NSObject, URLSessionDataDelegate {
    // MARK: URLSessionDelegate methods

    // Tells the URL session that the session has been invalidated.
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {

    }

    // Requests credentials from the delegate in response to a session-level authentication request from the remote server.
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

    }

    // MARK: URLSessionTaskDelegate methods

    // Tells the delegate that the task finished transferring data.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {

    }

    // Tells the delegate that the remote server requested an HTTP redirect.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {

    }

    // Periodically informs the delegate of the progress of sending body content to the server.
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {

    }

    // Tells the delegate when a task requires a new request body stream to send to the remote server.
    func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {

    }

    // Requests credentials from the delegate in response to an authentication request from the remote server.
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

    }

    // Tells the delegate that the task is waiting until suitable connectivity is available before beginning the network load.
    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {

    }

    // MARK: URLSessionDataDelegate methods

    // Tells the delegate that the data task received the initial reply (headers) from the server.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {

    }

    // Tells the delegate that the data task has received some of the expected data.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {

    }

    // Asks the delegate whether the data (or upload) task should store the response in the cache.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse, completionHandler: @escaping (CachedURLResponse?) -> Void) {

    }
}

public class EventSource: NSObject, URLSessionDataDelegate {

    private let config: Config

    private let delegateQueue: DispatchQueue = DispatchQueue(label: "ESDelegateQueue")
    private var readyState: ReadyState = .raw

    private var lastEventId: String?
    private var reconnectTime: TimeInterval?
    private var connectedTime: Date?

    private var reconnectionAttempts: Int = 0
    private var errorHandlerAction: ConnectionErrorAction? = nil
    private let utf8LineParser: UTF8LineParser = UTF8LineParser()
    private var eventParser: EventParser!

    public init(config: Config) {
        self.config = config
        self.lastEventId = config.lastEventId
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

            self.log("Starting EventSource client")
            let connectionHandler: ConnectionHandler = (
                setReconnectionTime: { reconnectionTime in self.reconnectTime = reconnectionTime },
                setLastEventId: { eventId in self.lastEventId = eventId }
            )
            self.eventParser = EventParser(handler: self.config.handler, connectionHandler: connectionHandler)
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.httpAdditionalHeaders = ["Accept": "text/event-stream", "Cache-Control": "no-cache"]
            // TODO change queue
            let session = URLSession.init(configuration: sessionConfig, delegate: self, delegateQueue: nil)
            var urlRequest = URLRequest(url: self.config.url, cachePolicy: URLRequest.CachePolicy.reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 60.0)
            urlRequest.httpMethod = self.config.method
            urlRequest.httpBody = self.config.body
            urlRequest.setValue(self.lastEventId, forHTTPHeaderField: "Last-Event-ID")
            urlRequest.allHTTPHeaderFields?.merge(self.config.headers, uniquingKeysWith: { $1 })
            session.dataTask(with: urlRequest).resume()
        }
    }

    private func connect() {
        var reconnectionAttempts: Int = 0
        var errorHandlerAction: ConnectionErrorAction? = nil
    }

    private func dispatchError(error: Error) -> ConnectionErrorAction {
        let action: ConnectionErrorAction = config.connectionErrorHandler(error)
        if action != .shutdown {
            config.handler.onError(error: error)
        }
        return action
    }

    func getLastEventId() -> String? { lastEventId }

    // MARK: URLSessionDelegate methods

    // Tells the URL session that the session has been invalidated.
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        log("became invalid with error")
    }

    // MARK: URLSessionTaskDelegate methods

    // Tells the delegate that the task finished transferring data.
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        utf8LineParser.closeAndReset().forEach(eventParser.parse)
        // Send additional empty line to force a last dispatch
        eventParser.parse(line: "")

        log("finished transferring data")
        if let error = error {
            config.handler.onError(error: error)
            log("With error \(error)")
        }
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

        public init(handler: EventHandler, url: URL) {
            self.handler = handler
            self.url = url
        }
    }
}
