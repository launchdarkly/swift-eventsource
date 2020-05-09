import Foundation

class EventParser {
    private struct Constants {
        static let dataLabel: Substring = "data"
        static let idLabel: Substring = "id"
        static let eventLabel: Substring = "event"
        static let retryLabel: Substring = "retry"
        static let defaultEventName = "message"
    }

    private let handler: EventHandler
    private let connectionHandler: ConnectionHandler

    private var data: String = ""
    private var lastEventId: String?
    private var eventName: String = Constants.defaultEventName

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

    private func dropLeadingSpace(str: Substring) -> Substring {
        if str.first == " " {
            return str[str.index(after: str.startIndex)...]
        }
        return str
    }

    private func processField(field: Substring, value: Substring) {
        switch field {
        case Constants.dataLabel:
            if !data.isEmpty {
                data.append(contentsOf: "\n")
            }
            data.append(contentsOf: value)
        case Constants.idLabel:
            lastEventId = String(value)
        case Constants.eventLabel:
            eventName = String(value)
        case Constants.retryLabel:
            if value.allSatisfy(("0"..."9").contains), let reconnectionTime = Int64(value) {
                connectionHandler.setReconnectionTime(Double(reconnectionTime) * 0.001)
            }
        default: break
        }
    }

    private func dispatchEvent() {
        guard !data.isEmpty
        else { return }
        let messageEvent = MessageEvent(data: data, lastEventId: lastEventId)
        if let lastEventId = lastEventId {
            connectionHandler.setLastEventId(lastEventId)
        }
        handler.onMessage(event: eventName, messageEvent: messageEvent)
        data = ""
        eventName = Constants.defaultEventName
    }
}

private extension Array {
    /// Returns the element at the specified index if it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Element? {
        return index >= startIndex && index < endIndex ? self[index] : nil
    }
}
