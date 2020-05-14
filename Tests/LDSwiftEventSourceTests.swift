import XCTest
import Embassy
@testable import LDSwiftEventSource
import os.log

final class LDSwiftEventSourceTests: XCTestCase {
    static var server: DefaultHTTPServer!
    static var eventLoop: SelectorEventLoop!
    static var blockingQueue: BlockingQueue<[String: Any]>!
    static var logger: OSLog = OSLog(subsystem: "com.launchdarkly.swift-event-source", category: "LDTest")

    override class func setUp() {
        eventLoop = try! SelectorEventLoop(selector: try! SelectSelector())
        server = DefaultHTTPServer(eventLoop: eventLoop, port: 8080) {
            ( environ: [String: Any],
              startResponse: @escaping ((String, [(String, String)]) -> Void),
              sendBody: @escaping ((Data) -> Void)
            ) in
            os_log("Received request", log: logger, type: .info)
            blockingQueue.enqueue(item: environ)
        }
        try! server.start()
        DispatchQueue.global(qos: .background).async {
            os_log("Starting event loop", log: logger, type: .info)
            eventLoop.runForever()
        }
    }

    override class func tearDown() {
        eventLoop.stop()
        server.stop()
    }

    override func setUp() {
        LDSwiftEventSourceTests.blockingQueue = BlockingQueue()
    }

    func testConfigDefaults() {
        let handler = MockHandler()
        let url = URL(string: "abc")!
        let config = EventSource.Config(handler: handler, url: url)
        XCTAssertEqual(config.url, url)
        XCTAssertEqual(config.method, "GET")
        XCTAssertEqual(config.body, nil)
        XCTAssertEqual(config.lastEventId, nil)
        XCTAssertEqual(config.headers, [:])
        XCTAssertEqual(config.reconnectTime, 1.0)
        XCTAssertEqual(config.maxReconnectTime, 30.0)
        XCTAssertEqual(config.backoffResetThreshold, 60.0)
        XCTAssertEqual(config.idleTimeout, 300.0)
    }

    func testConfigModification() {
        let handler = MockHandler()
        let url = URL(string: "abc")!
        var config = EventSource.Config(handler: handler, url: url)

        let testBody = "test data".data(using: .utf8)
        let testHeaders = ["Authorization": "basic abc"]

        config.method = "REPORT"
        config.body = testBody
        config.lastEventId = "eventId"
        config.headers = testHeaders
        config.reconnectTime = 2.0
        config.maxReconnectTime = 60.0
        config.backoffResetThreshold = 120.0
        config.idleTimeout = 180.0

        XCTAssertEqual(config.url, url)
        XCTAssertEqual(config.method, "REPORT")
        XCTAssertEqual(config.body, testBody)
        XCTAssertEqual(config.lastEventId, "eventId")
        XCTAssertEqual(config.headers, testHeaders)
        XCTAssertEqual(config.reconnectTime, 2.0)
        XCTAssertEqual(config.maxReconnectTime, 60.0)
        XCTAssertEqual(config.backoffResetThreshold, 120.0)
        XCTAssertEqual(config.idleTimeout, 180.0)
    }

    func testLastEventIdSentOnInitialRequest() {
        let handler = MockHandler()
        let url = URL(string: "http://localhost:8080")!
        var config = EventSource.Config(handler: handler, url: url)

        config.lastEventId = "foo"

        let es = EventSource(config: config)
        es.start()

        let environ = LDSwiftEventSourceTests.blockingQueue.dequeue()

        XCTAssertEqual(environ["HTTP_LAST_EVENT_ID"] as? String, "foo")
        XCTAssertEqual(es.getLastEventId(), "foo")

        es.stop()
    }

    func testLastEventIdSentOnInitialRequest() {
        let handler = MockHandler()
        let url = URL(string: "http://localhost:8080")!
        var config = EventSource.Config(handler: handler, url: url)

        config.lastEventId = "foo"

        let es = EventSource(config: config)
        es.start()

        let environ = LDSwiftEventSourceTests.blockingQueue.dequeue()

        XCTAssertEqual(environ["HTTP_LAST_EVENT_ID"] as? String, "foo")
        XCTAssertEqual(es.getLastEventId(), "foo")

        es.stop()
    }

    static var allTests = [
        ("testConfigDefaults", testConfigDefaults),
        ("testConfigModification", testConfigModification)
    ]

}

class BlockingQueue<Element> {
    private let waiter: DispatchSemaphore = DispatchSemaphore(value: 0)
    private var items: [Element] = []

    var count: Int { get { items.count } }
    var isEmpty: Bool { get { items.isEmpty } }

    init() {

    }

    func enqueue(item: Element) {
        items.append(item)
        waiter.signal()
    }

    func dequeue() -> Element {
        let _ = waiter.wait(timeout: DispatchTime.now() + .seconds(10))
        return items.removeFirst()
    }
}

private class MockHandler: EventHandler {
    func onOpened() {

    }

    func onClosed() {

    }

    func onMessage(event: String, messageEvent: MessageEvent) {

    }

    func onComment(comment: String) {

    }

    func onError(error: Error) {

    }


}
