import Foundation
import Testing
@testable import LDSwiftEventSource

@Suite("EventParser")
final class EventParserTests {
    private let handler = MockHandler()
    private let parser: EventParser

    init() {
        parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
    }

    deinit {
        #expect(handler.events.maybeEvent() == nil)
    }

    // MARK: Retry time tests
    @Test func unsetRetryReturnsConfigured() {
        let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 5.0)
        #expect(parser.reset() == 5.0)
    }

    @Test func setsRetryTimeToSevenSeconds() {
        parser.parse(line: "retry: 7000")
        #expect(parser.reset() == 7.0)
        #expect(parser.getLastEventId() == "")
    }

    @Test func retryWithNoSpace() {
        parser.parse(line: "retry:7000")
        #expect(parser.reset() == 7.0)
        #expect(parser.getLastEventId() == "")
    }

    @Test func doesNotSetRetryTimeUnlessEntireValueIsNumeric() {
        parser.parse(line: "retry: 7000L")
        #expect(parser.reset() == 1.0)
    }

    @Test func safeToUseEmptyRetryTime() {
        parser.parse(line: "retry")
        #expect(parser.reset() == 1.0)
    }

    @Test func safeToAttemptToSetRetryToOutOfBoundsValue() {
        parser.parse(line: "retry: 10000000000000000000000000")
        #expect(parser.reset() == 1.0)
    }

    @Test func resetDoesNotResetRetry() {
        parser.parse(line: "retry: 7000")
        #expect(parser.reset() == 7.0)
        #expect(parser.reset() == 7.0)
    }

    @Test func retryNotChangedDuringOtherMessages() {
        parser.parse(line: "retry: 7000")
        parser.parse(line: "")
        parser.parse(line: ":123")
        parser.parse(line: "event: 123")
        parser.parse(line: "data: 123")
        parser.parse(line: "id: 123")
        parser.parse(line: "none: 123")
        parser.parse(line: "")
        #expect(parser.reset() == 7.0)
        _ = handler.events.maybeEvent()
        _ = handler.events.maybeEvent()
    }

    // MARK: Comment tests
    @Test func emptyComment() {
        parser.parse(line: ":")
        #expect(handler.events.maybeEvent() == .comment(""))
    }

    @Test func commentBody() {
        parser.parse(line: ": comment")
        #expect(handler.events.maybeEvent() == .comment(" comment"))
    }

    @Test func commentCanContainColon() {
        parser.parse(line: ":comment:line")
        #expect(handler.events.maybeEvent() == .comment("comment:line"))
    }

    // MARK: Message data tests
    @Test func dispatchesEmptyMessageData() {
        parser.parse(line: "data")
        parser.parse(line: "")
        parser.parse(line: "data:")
        parser.parse(line: "")
        parser.parse(line: "data: ")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "", lastEventId: "")))
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "", lastEventId: "")))
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "", lastEventId: "")))
    }

    @Test func doesNotRemoveTrailingSpaceWhenColonNotPresent() {
        parser.parse(line: "data ")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == nil)
    }

    @Test func emptyFirstDataAppendsNewline() {
        parser.parse(line: "data:")
        parser.parse(line: "data:")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "\n", lastEventId: "")))
    }

    @Test func dispatchesSingleLineMessage() {
        parser.parse(line: "data: hello")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "hello", lastEventId: "")))
    }

    @Test func emptyDataWithBufferedDataAppendsNewline() {
        parser.parse(line: "data: data1")
        parser.parse(line: "data: ")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "data1\n", lastEventId: "")))
    }

    @Test func dataResetAfterEvent() {
        parser.parse(line: "data: hello")
        parser.parse(line: "")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "hello", lastEventId: "")))
    }

    @Test func removesOnlyFirstSpace() {
        parser.parse(line: "data:  {\"foo\": \"bar baz\"}")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: " {\"foo\": \"bar baz\"}", lastEventId: "")))
    }

    @Test func doesNotRemoveOtherWhitespace() {
        parser.parse(line: "data:\t{\"foo\": \"bar baz\"}")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "\t{\"foo\": \"bar baz\"}", lastEventId: "")))
    }

    @Test func allowsNoLeadingSpace() {
        parser.parse(line: "data:{\"foo\": \"bar baz\"}")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "{\"foo\": \"bar baz\"}", lastEventId: "")))
    }

    @Test func multipleDataDispatch() {
        parser.parse(line: "data: data1")
        parser.parse(line: "data: data2")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "data1\ndata2", lastEventId: "")))
    }

    // MARK: Event type tests
    @Test func dispatchesMessageWithCustomEventType() {
        parser.parse(line: "event: customEvent")
        parser.parse(line: "data: hello")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .message("customEvent", MessageEvent(data: "hello", lastEventId: "")))
    }

    @Test func customEventTypeWithoutSpace() {
        parser.parse(line: "event:customEvent")
        parser.parse(line: "data: hello")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .message("customEvent", MessageEvent(data: "hello", lastEventId: "")))
    }

    @Test func customEventAfterData() {
        parser.parse(line: "data: hello")
        parser.parse(line: "event: customEvent")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .message("customEvent", MessageEvent(data: "hello", lastEventId: "")))
    }

    @Test func emptyEventTypesDefaultToMessage() {
        ["event", "event:", "event: "].forEach {
            parser.parse(line: $0)
            parser.parse(line: "data: foo")
            parser.parse(line: "")
        }
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "foo", lastEventId: "")))
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "foo", lastEventId: "")))
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "foo", lastEventId: "")))
    }

    @Test func dispatchWithoutDataResetsMessageType() {
        parser.parse(line: "event: customEvent")
        parser.parse(line: "")
        parser.parse(line: "data: foo")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "foo", lastEventId: "")))
    }

    @Test func dispatchWithDataResetsMessageType() {
        parser.parse(line: "event: customEvent")
        parser.parse(line: "data: foo")
        parser.parse(line: "")
        parser.parse(line: "data: bar")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .message("customEvent", MessageEvent(data: "foo", lastEventId: "")))
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "bar", lastEventId: "")))
    }

    // MARK: Last event ID tests
    @Test func lastEventIdNotReturnedUntilDispatch() {
        #expect(parser.getLastEventId() == "")
        parser.parse(line: "id: 1")
        #expect(handler.events.maybeEvent() == nil)
        #expect(parser.getLastEventId() == "")
    }

    @Test func recordsLastEventIdWithoutData() {
        parser.parse(line: "id: 1")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == nil)
        #expect(parser.getLastEventId() == "1")
    }

    @Test func eventIdIncludedInMessageEvent() {
        parser.parse(line: "data: hello")
        parser.parse(line: "id: 1")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "hello", lastEventId: "1")))
    }

    @Test func reusesEventIdIfNotSet() {
        parser.parse(line: "data: hello")
        parser.parse(line: "id: reused")
        parser.parse(line: "")
        parser.parse(line: "data: world")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "hello", lastEventId: "reused")))
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "world", lastEventId: "reused")))
        #expect(parser.getLastEventId() == "reused")
    }

    @Test func eventIdSetTwiceInEvent() {
        parser.parse(line: "id: abc")
        parser.parse(line: "id: def")
        parser.parse(line: "data")
        #expect(parser.getLastEventId() == "")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "", lastEventId: "def")))
        #expect(parser.getLastEventId() == "def")
    }

    @Test func eventIdContainingNullIgnored() {
        parser.parse(line: "id: reused")
        parser.parse(line: "id: abc\u{0000}def")
        parser.parse(line: "data")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "", lastEventId: "reused")))
        #expect(parser.getLastEventId() == "reused")
    }

    @Test func resetDoesResetLastEventIdBuffer() {
        parser.parse(line: "id: 1")
        _ = parser.reset()
        parser.parse(line: "data: hello")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "hello", lastEventId: "")))
        #expect(parser.getLastEventId() == "")
    }

    @Test func resetDoesNotResetLastEventId() {
        parser.parse(line: "id: 1")
        parser.parse(line: "")
        _ = parser.reset()
        parser.parse(line: "data: hello")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .message("message", MessageEvent(data: "hello", lastEventId: "1")))
        #expect(parser.getLastEventId() == "1")
    }

    // MARK: Mixed and other tests
    @Test func repeatedEmptyLines() {
        parser.parse(line: "")
        parser.parse(line: "")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == nil)
    }

    @Test func nothingDoneForInvalidFieldName() {
        parser.parse(line: "invalid: bar")
        #expect(handler.events.maybeEvent() == nil)
    }

    @Test func invalidFieldNameIgnoredInEvent() {
        parser.parse(line: "data: foo")
        parser.parse(line: "invalid: bar")
        parser.parse(line: "event: msg")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .message("msg", MessageEvent(data: "foo", lastEventId: "")))
    }

    @Test func commentInEvent() {
        parser.parse(line: "data: foo")
        parser.parse(line: ":bar")
        parser.parse(line: "event: msg")
        parser.parse(line: "")
        #expect(handler.events.maybeEvent() == .comment("bar"))
        #expect(handler.events.maybeEvent() == .message("msg", MessageEvent(data: "foo", lastEventId: "")))
    }
}
