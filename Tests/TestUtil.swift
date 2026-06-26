import XCTest

#if os(Linux) || os(Windows)
import FoundationNetworking
#endif

// A thread-safe queue used to hand events from the background threads that drive
// the mocks (the URLSession delegate queue, the URLProtocol loading thread) to the
// test thread, which blocks waiting for them. A reference type guarded by an
// `NSCondition` so it can be shared across those threads; `@unchecked Sendable`
// because the locking the compiler cannot verify is what makes the access safe.
final class EventSink<T>: @unchecked Sendable {
    private let condition = NSCondition()
    private var receivedEvents: [T] = []

    func record(_ event: T) {
        condition.lock()
        defer { condition.unlock() }
        receivedEvents.append(event)
        condition.signal()
    }

    func expectEvent(maxWait: TimeInterval = 1.0) -> T {
        let deadline = Date(timeIntervalSinceNow: maxWait)
        condition.lock()
        defer { condition.unlock() }
        while receivedEvents.isEmpty {
            guard condition.wait(until: deadline)
            else {
                XCTFail("Expected mock handler to be called")
                return (nil as T?)!
            }
        }
        return receivedEvents.removeFirst()
    }

    func maybeEvent() -> T? {
        condition.lock()
        defer { condition.unlock() }
        return receivedEvents.isEmpty ? nil : receivedEvents.removeFirst()
    }

    func expectNoEvent(within: TimeInterval = 0.1) {
        let deadline = Date(timeIntervalSinceNow: within)
        condition.lock()
        defer { condition.unlock() }
        while receivedEvents.isEmpty {
            guard condition.wait(until: deadline)
            else { return }
        }
        XCTFail("Expected no events in sink, found \(String(describing: receivedEvents.first))")
    }

    func reset() {
        condition.lock()
        defer { condition.unlock() }
        receivedEvents.removeAll()
    }
}

// A lock-protected reference cell so tests can read and mutate a value from inside
// the `@Sendable` configuration closures (e.g. connectionErrorHandler) without
// tripping the concurrent-capture checks of the v6 language mode.
final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: T

    init(_ value: T) { storedValue = value }

    var value: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedValue = newValue
        }
    }
}

final class RequestHandler {
    let proto: URLProtocol
    let request: URLRequest
    let client: URLProtocolClient?

    var stopped = false

    init(proto: URLProtocol, request: URLRequest, client: URLProtocolClient?) {
        self.proto = proto
        self.request = request
        self.client = client
    }

    func respond(statusCode: Int) {
        let headers = ["Content-Type": "text/event-stream; charset=utf-8", "Transfer-Encoding": "chunked"]
        let resp = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(proto, didReceive: resp, cacheStoragePolicy: .notAllowed)
    }

    func respond(didLoad: String) {
        respond(didLoad: Data(didLoad.utf8))
    }

    func respond(didLoad: Data) {
        client?.urlProtocol(proto, didLoad: didLoad)
    }

    func finishWith(error: Error) {
        client?.urlProtocol(proto, didFailWithError: error)
    }

    func finish() {
        client?.urlProtocolDidFinishLoading(proto)
    }

    func stop() {
        stopped = true
    }
}

class MockingProtocol: URLProtocol {
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canInit(with task: URLSessionTask) -> Bool { true }

    static let requested = EventSink<RequestHandler>()

    class func resetRequested() {
        requested.reset()
    }

    private var currentlyLoading: RequestHandler?

    override func startLoading() {
        let handler = RequestHandler(proto: self, request: request, client: client)
        currentlyLoading = handler
        MockingProtocol.requested.record(handler)
    }

    override func stopLoading() {
        currentlyLoading?.stop()
        currentlyLoading = nil
    }
}

extension URLRequest {
    func bodyStreamAsData() -> Data? {
        guard let bodyStream = self.httpBodyStream
        else { return nil }

        bodyStream.open()
        defer { bodyStream.close() }

        let bufSize: Int = 16
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }

        var data = Data()
        while bodyStream.hasBytesAvailable {
            let readDat = bodyStream.read(buf, maxLength: bufSize)
            data.append(buf, count: readDat)
        }
        return data
    }
}
