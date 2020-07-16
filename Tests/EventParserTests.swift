import XCTest
@testable import LDSwiftEventSource

class MockEventHandler: EventHandler {
    enum ReceivedEvent: Equatable {
        case message(String, MessageEvent)
        case comment(String)
    }

    var received: [ReceivedEvent] = []

    func onMessage(eventType: String, messageEvent: MessageEvent) {
        received.append(.message(eventType, messageEvent))
    }

    func onComment(comment: String) {
        received.append(.comment(comment))
    }

    func reset() {
        received = []
    }

    // Never called by EventParser
    func onOpened() { }
    func onClosed() { }
    func onError(error: Error) { }
}

final class EventParserTests: XCTestCase {
    var receivedReconnectionTime: TimeInterval? = nil
    var receivedLastEventId: String? = nil
    lazy var connectionHandler: ConnectionHandler = { (setReconnectionTime: { self.receivedReconnectionTime = $0 },
                                                       setLastEventId: { self.receivedLastEventId = $0 }) }()
    let eventHandler = MockEventHandler()
    var parser: EventParser!

    override func setUp() {
        receivedReconnectionTime = nil
        receivedLastEventId = nil
        eventHandler.reset()
        parser = EventParser(handler: eventHandler, connectionHandler: connectionHandler)
    }

    func testDispatchesSingleLineMessage() {
        parser.parse(line: "data: hello")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("message", MessageEvent(data: "hello", lastEventId: nil))])
        XCTAssertEqual(receivedReconnectionTime, nil)
        XCTAssertEqual(receivedLastEventId, nil)
    }

    func testDoesNotFireMultipleTimesIfSeveralEmptyLines() {
        parser.parse(line: "data: hello")
        parser.parse(line: "")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("message", MessageEvent(data: "hello", lastEventId: nil))])
    }

    func testDispatchesSingleLineMessageWIthId() {
        parser.parse(line: "data: hello")
        parser.parse(line: "id: 1")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("message", MessageEvent(data: "hello", lastEventId: "1"))])
        XCTAssertEqual(receivedLastEventId, "1")
    }

    func testDispatchesSingleLineMessageWithCustomEvent() {
        parser.parse(line: "data: hello")
        parser.parse(line: "event: customEvent")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("customEvent", MessageEvent(data: "hello", lastEventId: nil))])
    }

    func testSendsCommentsForLinesStartingWithColon() {
        parser.parse(line: ":first comment")
        parser.parse(line: "data: hello")
        parser.parse(line: ":second comment")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.comment("first comment"),
                                               .comment("second comment"),
                                               .message("message", MessageEvent(data: "hello", lastEventId: nil))])
    }

    func testSetsRetryTimeToSevenSeconds() {
        parser.parse(line: "retry: 7000")
        parser.parse(line: "")
        XCTAssertEqual(receivedReconnectionTime, 7.0)
    }

    func testDoesNotSetRetryTimeUnlessEntireValueIsNumeric() {
        parser.parse(line: "retry: 7000L")
        parser.parse(line: "")
        XCTAssertEqual(receivedReconnectionTime, nil)
    }

    func testReusesEventIdIfNotSet() {
        parser.parse(line: "data: hello")
        parser.parse(line: "id: reused")
        parser.parse(line: "")
        parser.parse(line: "data: world")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("message", MessageEvent(data: "hello", lastEventId: "reused")),
                                               .message("message", MessageEvent(data: "world", lastEventId: "reused"))])
        XCTAssertEqual(receivedLastEventId, "reused")
    }

    func testRemovesOnlyFirstSpace() {
        parser.parse(line: "data: {\"foo\": \"bar baz\"}")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("message", MessageEvent(data: "{\"foo\": \"bar baz\"}", lastEventId: nil))])
    }

    func testAllowsNoLeadingSpace() {
        parser.parse(line: "data:{\"foo\": \"bar baz\"}")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("message", MessageEvent(data: "{\"foo\": \"bar baz\"}", lastEventId: nil))])
    }

    func testDoesNotDispatchEmptyData() {
        parser.parse(line: "data:")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [])
    }

    func testOnlyLeadingSpaceTreatedAsEmpty() {
        parser.parse(line: "data: ")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [])
    }

    func testLineWithoutColonTreatedAsFieldNameWithEmptyData() {
        parser.parse(line: "event")
        parser.parse(line: "data: foo")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("", MessageEvent(data: "foo", lastEventId: nil))])
    }

    func testMultipleDataDispatch() {
        parser.parse(line: "data: data1")
        parser.parse(line: "data: data2")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("message", MessageEvent(data: "data1\ndata2", lastEventId: nil))])
    }

    func testEmptyDataWithBufferedDataAppendsNewline() {
        parser.parse(line: "data: data1")
        parser.parse(line: "data: ")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("message", MessageEvent(data: "data1\n", lastEventId: nil))])
    }

    func testCommentCanContainColon() {
        parser.parse(line: ":comment:line")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.comment("comment:line")])
    }

    func testInvalidFieldNameIgnoredInEvent() {
        parser.parse(line: "data: foo")
        parser.parse(line: "invalid: bar")
        parser.parse(line: "event: msg")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("msg", MessageEvent(data: "foo", lastEventId: nil))])
    }

    func testEventNameResetAfterDispatch() {
        parser.parse(line: "data: foo")
        parser.parse(line: "event: msg")
        parser.parse(line: "")
        parser.parse(line: "data: bar")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("msg", MessageEvent(data: "foo", lastEventId: nil)),
                                               .message("message", MessageEvent(data: "bar", lastEventId: nil))])
    }

    static var allTests = [
        ("testDispatchesSingleLineMessage", testDispatchesSingleLineMessage),
        ("testDoesNotFireMultipleTimesIfSeveralEmptyLines", testDoesNotFireMultipleTimesIfSeveralEmptyLines),
        ("testDispatchesSingleLineMessageWIthId", testDispatchesSingleLineMessageWIthId),
        ("testDispatchesSingleLineMessageWithCustomEvent", testDispatchesSingleLineMessageWithCustomEvent),
        ("testSendsCommentsForLinesStartingWithColon", testSendsCommentsForLinesStartingWithColon),
        ("testSetsRetryTimeToSevenSeconds", testSetsRetryTimeToSevenSeconds),
        ("testDoesNotSetRetryTimeUnlessEntireValueIsNumeric", testDoesNotSetRetryTimeUnlessEntireValueIsNumeric),
        ("testReusesEventIdIfNotSet", testReusesEventIdIfNotSet),
        ("testRemovesOnlyFirstSpace", testRemovesOnlyFirstSpace),
        ("testAllowsNoLeadingSpace", testAllowsNoLeadingSpace),
        ("testDoesNotDispatchEmptyData", testDoesNotDispatchEmptyData),
        ("testOnlyLeadingSpaceTreatedAsEmpty", testOnlyLeadingSpaceTreatedAsEmpty),
        ("testLineWithoutColonTreatedAsFieldNameWithEmptyData", testLineWithoutColonTreatedAsFieldNameWithEmptyData),
        ("testMultipleDataDispatch", testMultipleDataDispatch),
        ("testEmptyDataWithBufferedDataAppendsNewline", testEmptyDataWithBufferedDataAppendsNewline),
        ("testCommentCanContainColon", testCommentCanContainColon),
        ("testInvalidFieldNameIgnoredInEvent", testInvalidFieldNameIgnoredInEvent),
        ("testEventNameResetAfterDispatch", testEventNameResetAfterDispatch)
    ]
}
