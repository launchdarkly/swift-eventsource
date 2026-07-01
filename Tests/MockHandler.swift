@testable import LDSwiftEventSource

enum ReceivedEvent: Equatable {
    case opened(headers: [String: String])
    case closed
    case message(String, MessageEvent)
    case comment(String)
    case error(EventSourceError)

    /// Maps a public `EventSourceEvent` to the test-side enum so stream output can be
    /// compared with the same `Equatable` the callback-based doubles use.
    init(_ event: EventSourceEvent) {
        switch event {
        case let .opened(headers):
            self = .opened(headers: headers)
        case .closed:
            self = .closed
        case let .message(eventType, messageEvent):
            self = .message(eventType, messageEvent)
        case let .comment(comment):
            self = .comment(comment)
        case let .error(error):
            self = .error(error)
        }
    }

    static func == (lhs: ReceivedEvent, rhs: ReceivedEvent) -> Bool {
        switch (lhs, rhs) {
        case (.opened, .opened):
            // Equality ignores headers; tests that care inspect them via EventCollector.expectOpened().
            return true
        case (.closed, .closed):
            return true
        case let (.message(typeLhs, eventLhs), .message(typeRhs, eventRhs)):
            return typeLhs == typeRhs && eventLhs == eventRhs
        case let (.comment(lhs), .comment(rhs)):
            return lhs == rhs
        case let (.error(lhs), .error(rhs)):
            // Compare the load-bearing fields; underlyingError isn't Equatable.
            return lhs.statusCode == rhs.statusCode && lhs.recoverable == rhs.recoverable
        default:
            return false
        }
    }
}

final class MockHandler: EventHandler {
    let events = EventSink<ReceivedEvent>()

    func onOpened(headers: [String: String]) { events.record(.opened(headers: headers)) }
    func onClosed() { events.record(.closed) }
    func onMessage(eventType: String, messageEvent: MessageEvent) { events.record(.message(eventType, messageEvent)) }
    func onComment(comment: String) { events.record(.comment(comment)) }
    func onError(_ error: EventSourceError) { events.record(.error(error)) }
}
