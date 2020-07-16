import XCTest
@testable import LDSwiftEventSource

final class LDSwiftEventSourceTests: XCTestCase {
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

    static var allTests = [
        ("testConfigDefaults", testConfigDefaults),
        ("testConfigModification", testConfigModification)
    ]
}

private class MockHandler: EventHandler {
    func onOpened() {

    }

    func onClosed() {

    }

    func onMessage(eventType: String, messageEvent: MessageEvent) {

    }

    func onComment(comment: String) {

    }

    func onError(error: Error) {

    }


}
