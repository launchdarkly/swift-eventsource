import Foundation

typealias ConnectionHandler = (setReconnectionTime: (TimeInterval) -> Void, setLastEventId: (String) -> Void)

class EventParser {
    private struct Constants {
        static let dataLabel: Substring = "data"
        static let idLabel: Substring = "id"
        static let eventLabel: Substring = "event"
        static let retryLabel: Substring = "retry"
    }

    private let handler: EventHandler
    private let connectionHandler: ConnectionHandler

    private var data: String = ""
    private var lastEventId: String?
    private var eventType: String = ""

    init(handler: EventHandler, connectionHandler: ConnectionHandler) {
        self.handler = handler
        self.connectionHandler = connectionHandler
    }

    func parse(line: String) {
        let splitByColon = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)

        switch (splitByColon[0], splitByColon[safe: 1]) {
        case ("", nil): // Empty line
            dispatchEvent()
        case let ("", .some(comment)): // Line starting with ':' is a comment
            handler.onComment(comment: String(comment))
        case let (field, data):
            processField(field: field, value: dropLeadingSpace(str: data ?? ""))
        }
    }

    func reset() {
        data = ""
        eventType = ""
    }

    private func dropLeadingSpace(str: Substring) -> Substring {
        if str.first == " " {
            return str[str.index(after: str.startIndex)...]
        }
        return str
    }

    private func processField(field: Substring, value: Substring) {
        switch field {
        case Constants.dataLabel:
            data.append(contentsOf: value)
            data.append(contentsOf: "\n")
        case Constants.idLabel:
            // See https://github.com/whatwg/html/issues/689 for reasoning on not setting lastEventId if the value
            // contains a null code point.
            if !value.contains("\u{0000}") {
                lastEventId = String(value)
            }
        case Constants.eventLabel:
            eventType = String(value)
        case Constants.retryLabel:
            if value.allSatisfy(("0"..."9").contains), let reconnectionTime = Int64(value) {
                connectionHandler.setReconnectionTime(Double(reconnectionTime) * 0.001)
            }
        default:
            break
        }
    }

    private func dispatchEvent() {
        if let lastEventId = lastEventId {
            connectionHandler.setLastEventId(lastEventId)
        }
        guard !data.isEmpty
        else {
            eventType = ""
            return
        }
        // remove the last LF
        _ = data.popLast()
        let messageEvent = MessageEvent(data: data, lastEventId: lastEventId)
        handler.onMessage(eventType: eventType.isEmpty ? "message" : eventType, messageEvent: messageEvent)
        data = ""
        eventType = ""
    }
}

private extension Array {
    /// Returns the element at the specified index if it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Element? {
        index >= startIndex && index < endIndex ? self[index] : nil
    }
}
