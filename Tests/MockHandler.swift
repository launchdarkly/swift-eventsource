@testable import LDSwiftEventSource

enum ReceivedEvent: Equatable {
    case opened, closed, message(String, MessageEvent), comment(String), error(Error)

    /// Maps a public `EventSourceEvent` to the test-side enum so stream output can be
    /// compared with the same `Equatable` the callback-based doubles use.
    init(_ event: EventSourceEvent) {
        switch event {
        case .opened:
            self = .opened
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
            return true
        case (.closed, .closed):
            return true
        case let (.message(typeLhs, eventLhs), .message(typeRhs, eventRhs)):
            return typeLhs == typeRhs && eventLhs == eventRhs
        case let (.comment(lhs), .comment(rhs)):
            return lhs == rhs
        case (.error, .error):
            return true
        default:
            return false
        }
    }
}

final class MockHandler: EventHandler {
    let events = EventSink<ReceivedEvent>()

    func onOpened() { events.record(.opened) }
    func onClosed() { events.record(.closed) }
    func onMessage(eventType: String, messageEvent: MessageEvent) { events.record(.message(eventType, messageEvent)) }
    func onComment(comment: String) { events.record(.comment(comment)) }
    func onError(error: Error) { events.record(.error(error)) }
}
