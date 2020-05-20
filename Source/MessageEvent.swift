import Foundation

/// Struct representing a received event from the stream.
public struct MessageEvent: Equatable, Hashable {
    /// Returns the event data.
    public let data: String
    /// The last seen event id, or the event id set in the Config if none have been received.
    public let lastEventId: String?

    public init(data: String, lastEventId: String? = nil) {
        self.data = data
        self.lastEventId = lastEventId
    }
}
