import Foundation

/**
 Type for a function that will take in the current HTTP headers and return a new set of HTTP headers to be used when
 connecting and reconnecting to a stream.
 */
public typealias HeaderTransform = @Sendable ([String: String]) -> [String: String]

/// Struct representing received event from the stream.
public struct MessageEvent: Equatable, Hashable, Sendable {
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

/**
 An error reported on the `EventSource.events` stream.

 Carries enough for a consumer to decide what the failure means without inspecting connection internals:
 - `recoverable == true`: the client has scheduled a reconnect with backoff. The stream stays open; this error is
   advisory (act on it, or ignore it and let the retry run).
 - `recoverable == false`: the client will not retry. This error is the last event before the stream finishes.

 The `headers` may carry service directives (e.g. an FDv1-fallback instruction) even on an error response, so they are
 load-bearing rather than diagnostic.
 */
public struct EventSourceError: Error, Sendable {
    /// The HTTP status code, when the failure was an unsuccessful HTTP response; `nil` for a transport/network error
    /// that never produced a response.
    public let statusCode: Int?
    /// The response headers (keys lowercased), when the failure was an HTTP response; empty for a transport error.
    public let headers: [String: String]
    /// Whether the client will retry this connection itself. When `true` the stream stays open and a reconnect is
    /// scheduled; when `false` the client stops and the stream finishes after this error.
    public let recoverable: Bool
    /// The underlying transport/network error, when the failure was not an HTTP response; `nil` for HTTP-status
    /// failures (use `statusCode`).
    public let underlyingError: (any Error)?

    /// Creates an `EventSourceError`.
    public init(
        statusCode: Int? = nil,
        headers: [String: String] = [:],
        recoverable: Bool,
        underlyingError: (any Error)? = nil
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.recoverable = recoverable
        self.underlyingError = underlyingError
    }
}

/// An event delivered through the `EventSource.events` stream.
public enum EventSourceEvent: Sendable {
    /**
     The stream connection has been opened.

     - Parameter headers: The response headers of the connection (keys lowercased). Carries service directives such as
       `x-ld-envid` / `x-ld-fd-fallback` that consumers may need.
     */
    case opened(headers: [String: String])
    /// The stream connection has been closed.
    case closed
    /**
     A message was received from the stream.

     - Parameter eventType: The type of the event.
     - Parameter messageEvent: The data for the event.
     */
    case message(eventType: String, MessageEvent)
    /// A comment line was received from the stream.
    case comment(String)
    /**
     An error occurred on the connection. This is a value in the stream, not necessarily a termination: a recoverable
     error is advisory and the client keeps retrying, while an unrecoverable error is the last event before the stream
     finishes. Refer to `EventSourceError.recoverable`.
     */
    case error(EventSourceError)
}

/// Internal protocol for an object that receives SSE events. The public surface is the `EventSource.events`
/// stream; conformers of this protocol feed it.
protocol EventHandler: Sendable {
    /// EventSource calls this method when the stream connection has been opened, with the response headers.
    func onOpened(headers: [String: String])

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
     EventSource calls this method when a connection failure occurs, after classifying it. The `EventSourceError`
     carries the status code (if any), response headers, and whether the client will retry.

     - Parameter error: The classified error.
     */
    func onError(_ error: EventSourceError)
}

/// Enum values representing the states of an EventSource
public enum ReadyState: String, Equatable, Sendable {
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
