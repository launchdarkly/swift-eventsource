import Foundation
import Testing
@testable import LDSwiftEventSource

#if os(Linux) || os(Windows)
import FoundationNetworking
#endif

// A thread-safe FIFO recorder for the synchronous parser tests, where events are produced (via
// MockHandler) and drained on the same test thread. `@unchecked Sendable` with an `NSLock` so
// MockHandler can stay `Sendable`; tests pull with the non-blocking `maybeEvent()`.
final class EventSink<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var receivedEvents: [T] = []

    func record(_ event: T) {
        lock.lock()
        defer { lock.unlock() }
        receivedEvents.append(event)
    }

    func maybeEvent() -> T? {
        lock.lock()
        defer { lock.unlock() }
        return receivedEvents.isEmpty ? nil : receivedEvents.removeFirst()
    }
}

// Poll-based, non-blocking sibling of `EventSink` for async tests. `record(_:)` is
// safe to call from any thread (the URLProtocol loading thread, the URLSession
// delegate queue, or a drain Task); the `expect*` methods are async and never block a
// thread, so they are safe to await on swift-testing's cooperative executor.
final class AsyncSink<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var receivedEvents: [T] = []

    func record(_ event: T) {
        lock.lock()
        defer { lock.unlock() }
        receivedEvents.append(event)
    }

    func maybeEvent() -> T? {
        lock.lock()
        defer { lock.unlock() }
        return receivedEvents.isEmpty ? nil : receivedEvents.removeFirst()
    }

    /// Polls up to `within` for an event, returning nil if none arrives in time.
    func expectEvent(within: Duration = .seconds(1)) async -> T? {
        let deadline = ContinuousClock.now + within
        while ContinuousClock.now < deadline {
            if let event = maybeEvent() {
                return event
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return maybeEvent()
    }

    /// Asserts that no event arrives within `within`. The window is a safety margin against an event
    /// that is in flight but not yet recorded; prefer `EventCollector.drained()` + `maybeEvent()` when
    /// the stream has already finished, which is deterministic.
    func expectNoEvent(within: Duration = .milliseconds(250)) async {
        try? await Task.sleep(for: within)
        if let event = maybeEvent() {
            Issue.record("Expected no events in sink, found \(String(describing: event))")
        }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        receivedEvents.removeAll()
    }
}

// Drains an `EventSource`'s event stream into an `AsyncSink` for assertions, mapping
// each `EventSourceEvent` to a `ReceivedEvent` (whose `Equatable` treats all errors as
// equal). The draining task runs until the stream finishes or `cancel()` is called.
final class EventCollector: Sendable {
    let events = AsyncSink<ReceivedEvent>()
    private let task: Task<Void, Never>

    init(_ source: AsyncStream<EventSourceEvent>) {
        let sink = events
        task = Task {
            for await event in source {
                sink.record(ReceivedEvent(event))
            }
        }
    }

    /// Awaits the drain task, which finishes once the source stream finishes (e.g. after `stop()`).
    /// Once this returns, every event the stream produced has been recorded, so the sink can be
    /// checked synchronously with `maybeEvent()` — no timing window. Only call this when the stream is
    /// expected to finish, or it will await indefinitely.
    func drained() async {
        await task.value
    }

    func cancel() {
        task.cancel()
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

    // Set when the URLProtocol's stopLoading runs (i.e. the connection was torn down). Lock-protected
    // because it is written on the loading thread and read from the test thread.
    let stopped = Box(false)

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
        stopped.value = true
    }
}

class MockingProtocol: URLProtocol {
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canInit(with task: URLSessionTask) -> Bool { true }

    static let requested = AsyncSink<RequestHandler>()

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
