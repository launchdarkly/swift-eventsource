@testable import LDSwiftEventSource

enum ReceivedEvent: Equatable {
    case opened, closed, message(String, MessageEvent), comment(String), error(Error)

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

class MockHandler: EventHandler {
    var events = EventSink<ReceivedEvent>()

    func onOpened() { events.record(.opened) }
    func onClosed() { events.record(.closed) }
    func onMessage(eventType: String, messageEvent: MessageEvent) { events.record(.message(eventType, messageEvent)) }
    func onComment(comment: String) { events.record(.comment(comment)) }
    func onError(error: Error) { events.record(.error(error)) }
}
