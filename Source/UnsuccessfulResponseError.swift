import Foundation

/// Error class that means the remote server returned an HTTP error.
public struct UnsuccessfulResponseError: Error {
    /// The HTTP response code received
    public let responseCode: Int

    init(responseCode: Int) {
        self.responseCode = responseCode
    }
}
