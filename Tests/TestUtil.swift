import XCTest

#if os(Linux)
import FoundationNetworking
#endif

struct EventSink<T> {
    private let semaphore = DispatchSemaphore(value: 0)
    private let queue = DispatchQueue(label: "EventSinkQueue." + UUID().uuidString)

    var receivedEvents: [T] = []

    mutating func record(_ event: T) {
        queue.sync { receivedEvents.append(event) }
        semaphore.signal()
    }

    mutating func expectEvent(maxWait: TimeInterval = 1.0) -> T {
        switch semaphore.wait(timeout: DispatchTime.now() + maxWait) {
        case .success:
            return queue.sync { receivedEvents.remove(at: 0) }
        case .timedOut:
            XCTFail("Expected mock handler to be called")
            return (nil as T?)!
        }
    }

    func expectNoEvent(within: TimeInterval = 0.1) {
        if case .success = semaphore.wait(timeout: DispatchTime.now() + within) {
            XCTFail("Expected no events in sink, found \(String(describing: receivedEvents.first))")
        }
    }
}

class RequestHandler {
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

    static var requested = EventSink<RequestHandler>()

    class func resetRequested() {
        requested = EventSink<RequestHandler>()
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
