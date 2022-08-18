import XCTest
@testable import LDSwiftEventSource

final class EventParserTests: XCTestCase {
    var handler: MockHandler!
    var parser: EventParser!

    override func setUp() {
        super.setUp()
        handler = MockHandler()
        parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
    }

    override func tearDown() {
        super.tearDown()
        XCTAssertNil(handler.events.maybeEvent())
    }

    // MARK: Retry time tests
    func testUnsetRetryReturnsConfigured() {
        parser = EventParser(handler: handler, initialEventId: "", initialRetry: 5.0)
        XCTAssertEqual(parser.reset(), 5.0)
    }

    func testSetsRetryTimeToSevenSeconds() {
        parser.parse(line: "retry: 7000")
        XCTAssertEqual(parser.reset(), 7.0)
        XCTAssertEqual(parser.getLastEventId(), "")
    }

    func testRetryWithNoSpace() {
        parser.parse(line: "retry:7000")
        XCTAssertEqual(parser.reset(), 7.0)
        XCTAssertEqual(parser.getLastEventId(), "")
    }

    func testDoesNotSetRetryTimeUnlessEntireValueIsNumeric() {
        parser.parse(line: "retry: 7000L")
        XCTAssertEqual(parser.reset(), 1.0)
    }

    func testSafeToUseEmptyRetryTime() {
        parser.parse(line: "retry")
        XCTAssertEqual(parser.reset(), 1.0)
    }

    func testSafeToAttemptToSetRetryToOutOfBoundsValue() {
        parser.parse(line: "retry: 10000000000000000000000000")
        XCTAssertEqual(parser.reset(), 1.0)
    }

    func testResetDoesNotResetRetry() {
        parser.parse(line: "retry: 7000")
        XCTAssertEqual(parser.reset(), 7.0)
        XCTAssertEqual(parser.reset(), 7.0)
    }

    func testRetryNotChangedDuringOtherMessages() {
        parser.parse(line: "retry: 7000")
        parser.parse(line: "")
        parser.parse(line: ":123")
        parser.parse(line: "event: 123")
        parser.parse(line: "data: 123")
        parser.parse(line: "id: 123")
        parser.parse(line: "none: 123")
        parser.parse(line: "")
        XCTAssertEqual(parser.reset(), 7.0)
        _ = handler.events.maybeEvent()
        _ = handler.events.maybeEvent()
    }

    // MARK: Comment tests
    func testEmptyComment() {
        parser.parse(line: ":")
        XCTAssertEqual(handler.events.maybeEvent(), .comment(""))
    }

    func testCommentBody() {
        parser.parse(line: ": comment")
        XCTAssertEqual(handler.events.maybeEvent(), .comment(" comment"))
    }

    func testCommentCanContainColon() {
        parser.parse(line: ":comment:line")
        XCTAssertEqual(handler.events.maybeEvent(), .comment("comment:line"))
    }

    // MARK: Message data tests
    func testDispatchesEmptyMessageData() {
        parser.parse(line: "data")
        parser.parse(line: "")
        parser.parse(line: "data:")
        parser.parse(line: "")
        parser.parse(line: "data: ")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "", lastEventId: "")))
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "", lastEventId: "")))
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "", lastEventId: "")))
    }

    func testDoesNotRemoveTrailingSpaceWhenColonNotPresent() {
        parser.parse(line: "data ")
        parser.parse(line: "")
        XCTAssertNil(handler.events.maybeEvent())
    }

    func testEmptyFirstDataAppendsNewline() {
        parser.parse(line: "data:")
        parser.parse(line: "data:")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "\n", lastEventId: "")))
    }

    func testDispatchesSingleLineMessage() {
        parser.parse(line: "data: hello")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "hello", lastEventId: "")))
    }

    func testEmptyDataWithBufferedDataAppendsNewline() {
        parser.parse(line: "data: data1")
        parser.parse(line: "data: ")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "data1\n", lastEventId: "")))
    }

    func testDataResetAfterEvent() {
        parser.parse(line: "data: hello")
        parser.parse(line: "")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "hello", lastEventId: "")))
    }

    func testRemovesOnlyFirstSpace() {
        parser.parse(line: "data:  {\"foo\": \"bar baz\"}")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: " {\"foo\": \"bar baz\"}", lastEventId: "")))
    }

    func testDoesNotRemoveOtherWhitespace() {
        parser.parse(line: "data:\t{\"foo\": \"bar baz\"}")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "\t{\"foo\": \"bar baz\"}", lastEventId: "")))
    }

    func testAllowsNoLeadingSpace() {
        parser.parse(line: "data:{\"foo\": \"bar baz\"}")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "{\"foo\": \"bar baz\"}", lastEventId: "")))
    }

    func testMultipleDataDispatch() {
        parser.parse(line: "data: data1")
        parser.parse(line: "data: data2")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "data1\ndata2", lastEventId: "")))
    }

    // MARK: Event type tests
    func testDispatchesMessageWithCustomEventType() {
        parser.parse(line: "event: customEvent")
        parser.parse(line: "data: hello")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .message("customEvent", MessageEvent(data: "hello", lastEventId: "")))
    }

    func testCustomEventTypeWithoutSpace() {
        parser.parse(line: "event:customEvent")
        parser.parse(line: "data: hello")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .message("customEvent", MessageEvent(data: "hello", lastEventId: "")))
    }

    func testCustomEventAfterData() {
        parser.parse(line: "data: hello")
        parser.parse(line: "event: customEvent")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .message("customEvent", MessageEvent(data: "hello", lastEventId: "")))
    }

    func testEmptyEventTypesDefaultToMessage() {
        ["event", "event:", "event: "].forEach {
            parser.parse(line: $0)
            parser.parse(line: "data: foo")
            parser.parse(line: "")
        }
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "foo", lastEventId: "")))
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "foo", lastEventId: "")))
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "foo", lastEventId: "")))
    }

    func testDispatchWithoutDataResetsMessageType() {
        parser.parse(line: "event: customEvent")
        parser.parse(line: "")
        parser.parse(line: "data: foo")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "foo", lastEventId: "")))
    }

    func testDispatchWithDataResetsMessageType() {
        parser.parse(line: "event: customEvent")
        parser.parse(line: "data: foo")
        parser.parse(line: "")
        parser.parse(line: "data: bar")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .message("customEvent", MessageEvent(data: "foo", lastEventId: "")))
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "bar", lastEventId: "")))
    }

    // MARK: Last event ID tests
    func testLastEventIdNotReturnedUntilDispatch() {
        XCTAssertEqual(parser.getLastEventId(), "")
        parser.parse(line: "id: 1")
        XCTAssertNil(handler.events.maybeEvent())
        XCTAssertEqual(parser.getLastEventId(), "")
    }

    func testRecordsLastEventIdWithoutData() {
        parser.parse(line: "id: 1")
        parser.parse(line: "")
        XCTAssertNil(handler.events.maybeEvent())
        XCTAssertEqual(parser.getLastEventId(), "1")
    }

    func testEventIdIncludedInMessageEvent() {
        parser.parse(line: "data: hello")
        parser.parse(line: "id: 1")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "hello", lastEventId: "1")))
    }

    func testReusesEventIdIfNotSet() {
        parser.parse(line: "data: hello")
        parser.parse(line: "id: reused")
        parser.parse(line: "")
        parser.parse(line: "data: world")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "hello", lastEventId: "reused")))
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "world", lastEventId: "reused")))
        XCTAssertEqual(parser.getLastEventId(), "reused")
    }

    func testEventIdSetTwiceInEvent() {
        parser.parse(line: "id: abc")
        parser.parse(line: "id: def")
        parser.parse(line: "data")
        XCTAssertEqual(parser.getLastEventId(), "")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "", lastEventId: "def")))
        XCTAssertEqual(parser.getLastEventId(), "def")
    }

    func testEventIdContainingNullIgnored() {
        parser.parse(line: "id: reused")
        parser.parse(line: "id: abc\u{0000}def")
        parser.parse(line: "data")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "", lastEventId: "reused")))
        XCTAssertEqual(parser.getLastEventId(), "reused")
    }

    func testResetDoesResetLastEventIdBuffer() {
        parser.parse(line: "id: 1")
        _ = parser.reset()
        parser.parse(line: "data: hello")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "hello", lastEventId: "")))
        XCTAssertEqual(parser.getLastEventId(), "")
    }

    func testResetDoesNotResetLastEventId() {
        parser.parse(line: "id: 1")
        parser.parse(line: "")
        _ = parser.reset()
        parser.parse(line: "data: hello")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .message("message", MessageEvent(data: "hello", lastEventId: "1")))
        XCTAssertEqual(parser.getLastEventId(), "1")
    }

    // MARK: Mixed and other tests
    func testRepeatedEmptyLines() {
        parser.parse(line: "")
        parser.parse(line: "")
        parser.parse(line: "")
        XCTAssertNil(handler.events.maybeEvent())
    }

    func testNothingDoneForInvalidFieldName() {
        parser.parse(line: "invalid: bar")
        XCTAssertNil(handler.events.maybeEvent())
    }

    func testInvalidFieldNameIgnoredInEvent() {
        parser.parse(line: "data: foo")
        parser.parse(line: "invalid: bar")
        parser.parse(line: "event: msg")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .message("msg", MessageEvent(data: "foo", lastEventId: "")))
    }

    func testCommentInEvent() {
        parser.parse(line: "data: foo")
        parser.parse(line: ":bar")
        parser.parse(line: "event: msg")
        parser.parse(line: "")
        XCTAssertEqual(handler.events.maybeEvent(), .comment("bar"))
        XCTAssertEqual(handler.events.maybeEvent(), .message("msg", MessageEvent(data: "foo", lastEventId: "")))
    }
}
