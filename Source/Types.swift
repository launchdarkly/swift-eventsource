import Foundation

/**
 Type for a function that will be notified when the `EventSource` client encounters a connection failure.

 This is different from `EventHandler.onError(error:)` in that it will not be called for other kinds of errors; also,
 it has the ability to tell the client to stop reconnecting by returning a `ConnectionErrorAction.shutdown`.
*/
public typealias ConnectionErrorHandler = (Error) -> ConnectionErrorAction

/**
 Type for a function that will take in the current HTTP headers and return a new set of HTTP headers to be used when
 connecting and reconnecting to a stream.
 */
public typealias HeaderTransform = ([String: String]) -> [String: String]

/// Potential actions a `ConnectionErrorHandler` can return
public enum ConnectionErrorAction {
    /**
     Specifies that the error should be logged normally and dispatched to the `EventHandler`. Connection retrying will
     proceed normally if appropriate.
     */
    case proceed
    /**
     Specifies that the connection should be immediately shut down and not retried. The error will not be dispatched
     to the `EventHandler`
     */
    case shutdown
}

/// Struct representing received event from the stream.
public struct MessageEvent: Equatable, Hashable {
    /// The event data of the event.
    public let data: String
    /// The last seen event id, or the event id set in the Config if none have been received.
    public let lastEventId: String

    /**
     Constructor for a `MessageEvent`

     - Parameter data: The `data` field of the `MessageEvent`.
     - Parameter eventType: The `lastEventId` field of the `MessageEvent`.
     */
    public init(data: String, lastEventId: String = "") {
        self.data = data
        self.lastEventId = lastEventId
    }
}

/// Protocol for an object that will receive SSE events.
public protocol EventHandler {
    /// EventSource calls this method when the stream connection has been opened.
    func onOpened()

    /// EventSource calls this method when the stream connection has been closed.
    func onClosed()

    /**
     EventSource calls this method when it has received a new event from the stream.

     - Parameter eventType: The type of the event.
     - Parameter messageEvent: The data for the event.
     */
    func onMessage(eventType: String, messageEvent: MessageEvent)

    /**
     EventSource calls this method when it has received a comment line from the stream.

     - Parameter comment: The comment received.
     */
    func onComment(comment: String)

    /**
     This method will be called for all exceptions that occur on the network connection (including an
     `UnsuccessfulResponseError` if the server returns an unexpected HTTP status), but only after the
     ConnectionErrorHandler (if any) has processed it.  If you need to do anything that affects the state of the
     connection, use ConnectionErrorHandler.

     - Parameter error: The error received.
     */
    func onError(error: Error)
}

/// Enum values representing the states of an EventSource
public enum ReadyState: String, Equatable {
    /// The `EventSource` client has not been started yet.
    case raw
    /// The `EventSource` client is attempting to make a connection.
    case connecting
    /// The `EventSource` client is active and listening for events.
    case open
    /// The connection has been closed or has failed, and the `EventSource` will attempt to reconnect.
    case closed
    /// The connection has been permanently closed and the `EventSource` not reconnect.
    case shutdown
}

/// Error class that indicates the remote server returned an unsuccessful HTTP response code.
public class UnsuccessfulResponseError: Error {
    /// The HTTP response code received.
    public let responseCode: Int

    /**
     Constructor for an `UnsuccessfulResponseError`.

     - Parameter responseCode: The HTTP response code of the unsuccessful response.
     */
    public init(responseCode: Int) {
        self.responseCode = responseCode
    }
}
