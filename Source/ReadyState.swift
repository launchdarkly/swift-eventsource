import Foundation

/// Enum values representing the states of an EventSource
public enum ReadyState: String, Equatable {
    /// The EventSource has not been started yet.
    case raw
    /// The EventSource is attempting to make a connection.
    case connecting
    /// The EventSource is active and the EventSource is listening for events.
    case open
    /// The connection has been closed or has failed, and the EventSource will attempt to reconnect.
    case closed
    /// The connection has been permanently closed and will not reconnect.
    case shutdown
}
