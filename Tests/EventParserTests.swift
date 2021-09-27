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
    var receivedReconnectionTime: TimeInterval?
    var receivedLastEventId: String?
    lazy var connectionHandler: ConnectionHandler = { (setReconnectionTime: { self.receivedReconnectionTime = $0 },
                                                       setLastEventId: { self.receivedLastEventId = $0 }) }()
    let eventHandler = MockEventHandler()
    var parser: EventParser!

    override func setUp() {
        super.setUp()
        resetMocks()
        parser = EventParser(handler: eventHandler, connectionHandler: connectionHandler)
    }

    override func tearDown() {
        super.tearDown()
        // Validate that `reset` completely resets the parser
        resetMocks()
        parser.reset()
        parser.parse(line: "data: hello")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received.count, 1)
        guard case let .message(eventType, event) = eventHandler.received[0]
        else {
            XCTFail("Unexpectedly received comment event")
            return
        }
        XCTAssertEqual(eventType, "message")
        XCTAssertEqual(event.data, "hello")
        XCTAssertNil(receivedReconnectionTime)
    }

    func resetMocks() {
        receivedReconnectionTime = nil
        receivedLastEventId = nil
        eventHandler.reset()
    }

    func expectNoConnectionHandlerCalls() {
        XCTAssertNil(receivedReconnectionTime)
        XCTAssertNil(receivedLastEventId)
    }

    // MARK: Retry time tests
    func testSetsRetryTimeToSevenSeconds() {
        parser.parse(line: "retry: 7000")
        XCTAssertEqual(receivedReconnectionTime, 7.0)
        XCTAssertNil(receivedLastEventId)
    }

    func testRetryWithNoSpace() {
        parser.parse(line: "retry:7000")
        XCTAssertEqual(receivedReconnectionTime, 7.0)
        XCTAssertNil(receivedLastEventId)
    }

    func testDoesNotSetRetryTimeUnlessEntireValueIsNumeric() {
        parser.parse(line: "retry: 7000L")
        expectNoConnectionHandlerCalls()
    }

    func testSafeToUseEmptyRetryTime() {
        parser.parse(line: "retry")
        expectNoConnectionHandlerCalls()
    }

    func testSafeToAttemptToSetRetryToOutOfBoundsValue() {
        parser.parse(line: "retry: 10000000000000000000000000")
        expectNoConnectionHandlerCalls()
    }

    // MARK: Comment tests
    func testEmptyComment() {
        parser.parse(line: ":")
        XCTAssertEqual(eventHandler.received, [.comment("")])
        expectNoConnectionHandlerCalls()
    }

    func testCommentBody() {
        parser.parse(line: ": comment")
        XCTAssertEqual(eventHandler.received, [.comment(" comment")])
        expectNoConnectionHandlerCalls()
    }

    func testCommentCanContainColon() {
        parser.parse(line: ":comment:line")
        XCTAssertEqual(eventHandler.received, [.comment("comment:line")])
        expectNoConnectionHandlerCalls()
    }

    // MARK: Message data tests
    func testDispatchesEmptyMessageData() {
        parser.parse(line: "data")
        parser.parse(line: "")
        parser.parse(line: "data:")
        parser.parse(line: "")
        parser.parse(line: "data: ")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received.count, 3)
        eventHandler.received.forEach {
            XCTAssertEqual($0, .message("message", MessageEvent(data: "", lastEventId: nil)))
        }
        expectNoConnectionHandlerCalls()
    }

    func testDoesNotRemoveTrailingSpaceWhenColonNotPresent() {
        parser.parse(line: "data ")
        parser.parse(line: "")
        XCTAssertTrue(eventHandler.received.isEmpty)
        expectNoConnectionHandlerCalls()
    }

    func testEmptyFirstDataAppendsNewline() {
        parser.parse(line: "data:")
        parser.parse(line: "data:")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("message", MessageEvent(data: "\n", lastEventId: nil))])
        expectNoConnectionHandlerCalls()
    }

    func testDispatchesSingleLineMessage() {
        parser.parse(line: "data: hello")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("message", MessageEvent(data: "hello", lastEventId: nil))])
        expectNoConnectionHandlerCalls()
    }

    func testEmptyDataWithBufferedDataAppendsNewline() {
        parser.parse(line: "data: data1")
        parser.parse(line: "data: ")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("message", MessageEvent(data: "data1\n", lastEventId: nil))])
    }

    func testDataResetAfterEvent() {
        parser.parse(line: "data: hello")
        parser.parse(line: "")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("message", MessageEvent(data: "hello", lastEventId: nil))])
        expectNoConnectionHandlerCalls()
    }

    func testRemovesOnlyFirstSpace() {
        parser.parse(line: "data:  {\"foo\": \"bar baz\"}")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("message", MessageEvent(data: " {\"foo\": \"bar baz\"}", lastEventId: nil))])
    }

    func testDoesNotRemoveOtherWhitespace() {
        parser.parse(line: "data:\t{\"foo\": \"bar baz\"}")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("message", MessageEvent(data: "\t{\"foo\": \"bar baz\"}", lastEventId: nil))])
    }

    func testAllowsNoLeadingSpace() {
        parser.parse(line: "data:{\"foo\": \"bar baz\"}")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("message", MessageEvent(data: "{\"foo\": \"bar baz\"}", lastEventId: nil))])
    }

    func testMultipleDataDispatch() {
        parser.parse(line: "data: data1")
        parser.parse(line: "data: data2")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("message", MessageEvent(data: "data1\ndata2", lastEventId: nil))])
    }

    // MARK: Event type tests
    func testDispatchesMessageWithCustomEventType() {
        parser.parse(line: "event: customEvent")
        parser.parse(line: "data: hello")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("customEvent", MessageEvent(data: "hello", lastEventId: nil))])
    }

    func testCustomEventTypeWithoutSpace() {
        parser.parse(line: "event:customEvent")
        parser.parse(line: "data: hello")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("customEvent", MessageEvent(data: "hello", lastEventId: nil))])
    }

    func testCustomEventAfterData() {
        parser.parse(line: "data: hello")
        parser.parse(line: "event: customEvent")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("customEvent", MessageEvent(data: "hello", lastEventId: nil))])
    }

    func testEmptyEventTypesDefaultToMessage() {
        ["event", "event:", "event: "].forEach {
            parser.parse(line: $0)
            parser.parse(line: "data: foo")
            parser.parse(line: "")
        }
        XCTAssertEqual(eventHandler.received.count, 3)
        eventHandler.received.forEach {
            XCTAssertEqual($0, .message("message", MessageEvent(data: "foo", lastEventId: nil)))
        }
    }

    func testDispatchWithoutDataResetsMessageType() {
        parser.parse(line: "event: customEvent")
        parser.parse(line: "")
        parser.parse(line: "data: foo")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("message", MessageEvent(data: "foo", lastEventId: nil))])
    }

    func testDispatchWithDataResetsMessageType() {
        parser.parse(line: "event: customEvent")
        parser.parse(line: "data: foo")
        parser.parse(line: "")
        parser.parse(line: "data: bar")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("customEvent", MessageEvent(data: "foo", lastEventId: nil)),
                                               .message("message", MessageEvent(data: "bar", lastEventId: nil))])
    }

    // MARK: Last event ID tests
    func testRecordsLastEventIdWithoutData() {
        parser.parse(line: "id: 1")
        // Should not have set until we dispatch with an empty line
        expectNoConnectionHandlerCalls()
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [])
        XCTAssertEqual(receivedLastEventId, "1")
        XCTAssertNil(receivedReconnectionTime)
    }

    func testEventIdIncludedInMessageEvent() {
        parser.parse(line: "data: hello")
        parser.parse(line: "id: 1")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("message", MessageEvent(data: "hello", lastEventId: "1"))])
        XCTAssertEqual(receivedLastEventId, "1")
        XCTAssertNil(receivedReconnectionTime)
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
        XCTAssertNil(receivedReconnectionTime)
    }

    func testEventIdSetTwiceInEvent() {
        parser.parse(line: "id: abc")
        // We want to only dispatch the ID when the event is completed
        XCTAssertNil(receivedLastEventId)
        parser.parse(line: "id: def")
        parser.parse(line: "data")
        XCTAssertNil(receivedLastEventId)
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("message", MessageEvent(data: "", lastEventId: "def"))])
        XCTAssertEqual(receivedLastEventId, "def")
        XCTAssertNil(receivedReconnectionTime)
    }

    func testEventIdContainingNullIgnored() {
        parser.parse(line: "id: reused")
        parser.parse(line: "id: abc\u{0000}def")
        parser.parse(line: "data")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("message", MessageEvent(data: "", lastEventId: "reused"))])
        XCTAssertEqual(receivedLastEventId, "reused")
        XCTAssertNil(receivedReconnectionTime)
    }

    func testResetDoesNotResetLastEventId() {
        parser.parse(line: "id: 1")
        parser.reset()
        parser.parse(line: "data: hello")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("message", MessageEvent(data: "hello", lastEventId: "1"))])
        XCTAssertEqual(receivedLastEventId, "1")
        XCTAssertNil(receivedReconnectionTime)
    }

    // MARK: Mixed and other tests
    func testRepeatedEmptyLines() {
        parser.parse(line: "")
        parser.parse(line: "")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [])
        expectNoConnectionHandlerCalls()
    }

    func testNothingDoneForInvalidFieldName() {
        parser.parse(line: "invalid: bar")
        XCTAssertEqual(eventHandler.received, [])
        expectNoConnectionHandlerCalls()
    }

    func testInvalidFieldNameIgnoredInEvent() {
        parser.parse(line: "data: foo")
        parser.parse(line: "invalid: bar")
        parser.parse(line: "event: msg")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.message("msg", MessageEvent(data: "foo", lastEventId: nil))])
    }

    func testCommentInEvent() {
        parser.parse(line: "data: foo")
        parser.parse(line: ":bar")
        parser.parse(line: "event: msg")
        parser.parse(line: "")
        XCTAssertEqual(eventHandler.received, [.comment("bar"),
                                               .message("msg", MessageEvent(data: "foo", lastEventId: nil))])
    }
}
