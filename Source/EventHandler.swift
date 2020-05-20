import Foundation

/// Protocol for an object that will receive SSE events.
public protocol EventHandler {
    /// EventSource calls this method when the stream connection has been opened.
    func onOpened()
    /// EventSource calls this method when the stream connection has been closed.
    func onClosed()
    /// EventSource calls this method when it has received a new event from the stream.
    func onMessage(event: String, messageEvent: MessageEvent)
    /// EventSource calls this method when it has received a comment line from the stream
    /// (any line starting with a colon).
    func onComment(comment: String)
    /// This method will be called for all exceptions that occur on the socket connection
    /// (including an {@link UnsuccessfulResponseError} if the server returns an unexpected HTTP status),
    /// but only after the ConnectionErrorHandler (if any) has processed it.  If you need to
    /// do anything that affects the state of the connection, use ConnectionErrorHandler.
    func onError(error: Error)
}
