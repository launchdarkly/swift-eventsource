import Foundation

// `parse`, `reset`, and event dispatch must be driven from a single serialized context (the
// EventSource delegate queue). `getLastEventId()` is the one entry point called concurrently — from
// arbitrary caller threads via `EventSource.getLastEventId()` — so the `lastEventId` it reads is
// lock-guarded. `@unchecked Sendable` reflects that split, which the compiler cannot verify.
final class EventParser: @unchecked Sendable {
    private struct Constants {
        static let dataLabel: Substring = "data"
        static let idLabel: Substring = "id"
        static let eventLabel: Substring = "event"
        static let retryLabel: Substring = "retry"
    }

    private let handler: EventHandler

    private var data: String = ""
    private var eventType: String = ""
    private var lastEventIdBuffer: String?
    private var currentRetry: TimeInterval

    // Written on the serialized parse path and read from any thread via `getLastEventId()`, so its
    // access is guarded by a lock.
    private let lastEventIdLock = NSLock()
    private var _lastEventId: String
    private var lastEventId: String {
        get {
            lastEventIdLock.lock()
            defer { lastEventIdLock.unlock() }
            return _lastEventId
        }
        set {
            lastEventIdLock.lock()
            defer { lastEventIdLock.unlock() }
            _lastEventId = newValue
        }
    }

    init(handler: EventHandler, initialEventId: String, initialRetry: TimeInterval) {
        self.handler = handler
        self._lastEventId = initialEventId
        self.currentRetry = initialRetry
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

    func getLastEventId() -> String { lastEventId }

    func reset() -> TimeInterval {
        data = ""
        eventType = ""
        lastEventIdBuffer = nil
        return currentRetry
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
                lastEventIdBuffer = String(value)
            }
        case Constants.eventLabel:
            eventType = String(value)
        case Constants.retryLabel:
            if value.allSatisfy({ ("0"..."9").contains($0) }), let reconnectionTime = Int64(value) {
                currentRetry = Double(reconnectionTime) * 0.001
            }
        default:
            break
        }
    }

    private func dispatchEvent() {
        lastEventId = lastEventIdBuffer ?? lastEventId
        lastEventIdBuffer = nil
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
