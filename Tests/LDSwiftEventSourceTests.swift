import XCTest
@testable import LDSwiftEventSource

#if os(Linux)
import FoundationNetworking
#endif

final class LDSwiftEventSourceTests: XCTestCase {
    private var mockHandler: MockHandler!

    override func setUp() {
        super.setUp()
        mockHandler = MockHandler()
        XCTAssertTrue(URLProtocol.registerClass(MockingProtocol.self))
    }

    override func tearDown() {
        super.tearDown()
        URLProtocol.unregisterClass(MockingProtocol.self)
        // Enforce that tests consume all mocked network requests
        MockingProtocol.requested.expectNoEvent(within: 0.01)
        MockingProtocol.resetRequested()
        // Enforce that tests consume all calls to the mock handler
        mockHandler.events.expectNoEvent(within: 0.01)
        mockHandler = nil
    }

    func testConfigDefaults() {
        let url = URL(string: "abc")!
        let config = EventSource.Config(handler: mockHandler, url: url)
        XCTAssertEqual(config.url, url)
        XCTAssertEqual(config.method, "GET")
        XCTAssertEqual(config.body, nil)
        XCTAssertEqual(config.lastEventId, "")
        XCTAssertEqual(config.headers, [:])
        XCTAssertEqual(config.reconnectTime, 1.0)
        XCTAssertEqual(config.maxReconnectTime, 30.0)
        XCTAssertEqual(config.backoffResetThreshold, 60.0)
        XCTAssertEqual(config.idleTimeout, 300.0)
        XCTAssertEqual(config.headerTransform(["abc": "123"]), ["abc": "123"])
        XCTAssertEqual(config.connectionErrorHandler(DummyError()), .proceed)
    }

    func testConfigModification() {
        let url = URL(string: "abc")!
        var config = EventSource.Config(handler: mockHandler, url: url)

        let testBody = "test data".data(using: .utf8)
        let testHeaders = ["Authorization": "basic abc"]

        config.method = "REPORT"
        config.body = testBody
        config.lastEventId = "eventId"
        config.headers = testHeaders
        config.reconnectTime = 2.0
        config.maxReconnectTime = 60.0
        config.backoffResetThreshold = 120.0
        config.idleTimeout = 180.0
        config.headerTransform = { _ in [:] }
        config.connectionErrorHandler = { _ in .shutdown }

        XCTAssertEqual(config.url, url)
        XCTAssertEqual(config.method, "REPORT")
        XCTAssertEqual(config.body, testBody)
        XCTAssertEqual(config.lastEventId, "eventId")
        XCTAssertEqual(config.headers, testHeaders)
        XCTAssertEqual(config.headerTransform(config.headers), [:])
        XCTAssertEqual(config.reconnectTime, 2.0)
        XCTAssertEqual(config.maxReconnectTime, 60.0)
        XCTAssertEqual(config.backoffResetThreshold, 120.0)
        XCTAssertEqual(config.idleTimeout, 180.0)
        XCTAssertEqual(config.connectionErrorHandler(DummyError()), .shutdown)
    }

    func testConfigUrlSession() {
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "abc")!)
        let defaultSessionConfig = config.urlSessionConfiguration
        XCTAssertEqual(defaultSessionConfig.timeoutIntervalForRequest, 300.0)
        XCTAssertEqual(defaultSessionConfig.httpAdditionalHeaders?["Accept"] as? String, "text/event-stream")
        XCTAssertEqual(defaultSessionConfig.httpAdditionalHeaders?["Cache-Control"] as? String, "no-cache")
        // Configuration should return a fresh session configuration each retrieval
        XCTAssertTrue(defaultSessionConfig !== config.urlSessionConfiguration)
        // Updating idleTimeout should effect session config
        config.idleTimeout = 600.0
        XCTAssertEqual(config.urlSessionConfiguration.timeoutIntervalForRequest, 600.0)
        XCTAssertEqual(defaultSessionConfig.timeoutIntervalForRequest, 300.0)
        // Updating returned urlSessionConfiguration without setting should not update the Config until set
        let sessionConfig = config.urlSessionConfiguration
        sessionConfig.allowsCellularAccess = false
        XCTAssertTrue(config.urlSessionConfiguration.allowsCellularAccess)
        config.urlSessionConfiguration = sessionConfig
        XCTAssertFalse(config.urlSessionConfiguration.allowsCellularAccess)
        XCTAssertTrue(sessionConfig !== config.urlSessionConfiguration)
    }

    func testLastEventIdFromConfig() {
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "abc")!)
        var es = EventSource(config: config)
        XCTAssertEqual(es.getLastEventId(), "")
        config.lastEventId = "def"
        es = EventSource(config: config)
        XCTAssertEqual(es.getLastEventId(), "def")
    }

    func testCreatedSession() {
        let config = EventSource.Config(handler: mockHandler, url: URL(string: "abc")!)
        let session = EventSourceDelegate(config: config).createSession()
        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, config.idleTimeout)
        XCTAssertEqual(session.configuration.httpAdditionalHeaders?["Accept"] as? String, "text/event-stream")
        XCTAssertEqual(session.configuration.httpAdditionalHeaders?["Cache-Control"] as? String, "no-cache")
    }

    func testCreateRequest() {
        // 192.0.2.1 is assigned as TEST-NET-1 reserved usage.
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "http://192.0.2.1")!)
        // Testing default configs
        var request = EventSourceDelegate(config: config).createRequest()
        XCTAssertEqual(request.url, config.url)
        XCTAssertEqual(request.httpMethod, config.method)
        XCTAssertEqual(request.httpBody, config.body)
        XCTAssertEqual(request.timeoutInterval, config.idleTimeout)
        XCTAssertEqual(request.allHTTPHeaderFields, config.headers)
        // Testing customized configs
        let testBody = "test data".data(using: .utf8)
        let testHeaders = ["removing": "a", "updating": "b"]
        let overrideHeaders = ["updating": "c", "last-event-id": "eventId2"]
        config.method = "REPORT"
        config.body = testBody
        config.lastEventId = "eventId"
        config.headers = testHeaders
        config.idleTimeout = 180.0
        config.headerTransform = { provided in
            XCTAssertEqual(provided, ["removing": "a", "updating": "b", "Last-Event-Id": "eventId"])
            return overrideHeaders
        }
        request = EventSourceDelegate(config: config).createRequest()
        XCTAssertEqual(request.url, config.url)
        XCTAssertEqual(request.httpMethod, config.method)
        XCTAssertEqual(request.httpBody, config.body)
        XCTAssertEqual(request.timeoutInterval, config.idleTimeout)
        XCTAssertEqual(request.allHTTPHeaderFields, overrideHeaders)
    }

    func testDispatchError() {
        var connectionErrorHandlerCallCount = 0
        var connectionErrorAction: ConnectionErrorAction = .proceed
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "abc")!)
        config.connectionErrorHandler = { _ in
            connectionErrorHandlerCallCount += 1
            return connectionErrorAction
        }
        let es = EventSourceDelegate(config: config)
        XCTAssertEqual(es.dispatchError(error: DummyError()), .proceed)
        XCTAssertEqual(connectionErrorHandlerCallCount, 1)
        guard case .error(let err) = mockHandler.events.expectEvent(), err is DummyError
        else {
            XCTFail("handler should receive error if EventSource is not shutting down")
            return
        }
        mockHandler.events.expectNoEvent()
        connectionErrorAction = .shutdown
        XCTAssertEqual(es.dispatchError(error: DummyError()), .shutdown)
        XCTAssertEqual(connectionErrorHandlerCallCount, 2)
    }

    func sessionWithMockProtocol() -> URLSessionConfiguration {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockingProtocol.self] + (sessionConfig.protocolClasses ?? [])
        return sessionConfig
    }

#if !os(Linux)
    func testStartDefaultRequest() {
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        let es = EventSource(config: config)
        es.start()
        let handler = MockingProtocol.requested.expectEvent()
        XCTAssertEqual(handler.request.url, config.url)
        XCTAssertEqual(handler.request.httpMethod, config.method)
        XCTAssertEqual(handler.request.httpBody, config.body)
        XCTAssertEqual(handler.request.timeoutInterval, config.idleTimeout)
        XCTAssertEqual(handler.request.allHTTPHeaderFields?["Accept"], "text/event-stream")
        XCTAssertEqual(handler.request.allHTTPHeaderFields?["Cache-Control"], "no-cache")
        XCTAssertNil(handler.request.allHTTPHeaderFields?["Last-Event-Id"])
        es.stop()
    }

    func testStartRequestWithConfiguration() {
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        config.method = "REPORT"
        config.body = Data("test body".utf8)
        config.idleTimeout = 500.0
        config.lastEventId = "abc"
        config.headers = ["X-LD-Header": "def"]
        let es = EventSource(config: config)
        es.start()
        let handler = MockingProtocol.requested.expectEvent()
        XCTAssertEqual(handler.request.url, config.url)
        XCTAssertEqual(handler.request.httpMethod, config.method)
        XCTAssertEqual(handler.request.bodyStreamAsData(), config.body)
        XCTAssertEqual(handler.request.timeoutInterval, config.idleTimeout)
        XCTAssertEqual(handler.request.allHTTPHeaderFields?["Accept"], "text/event-stream")
        XCTAssertEqual(handler.request.allHTTPHeaderFields?["Cache-Control"], "no-cache")
        XCTAssertEqual(handler.request.allHTTPHeaderFields?["Last-Event-Id"], config.lastEventId)
        XCTAssertEqual(handler.request.allHTTPHeaderFields?["X-LD-Header"], "def")
        es.stop()
    }
    
    func testStartRequestIsNotReentrant() {
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        let es = EventSource(config: config)
        es.start()
        es.start()
        _ = MockingProtocol.requested.expectEvent()
        MockingProtocol.requested.expectNoEvent()
        es.stop()
    }

    func testSuccessfulResponseOpens() {
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        let es = EventSource(config: config)
        es.start()
        let handler = MockingProtocol.requested.expectEvent()
        handler.respond(statusCode: 200)
        XCTAssertEqual(mockHandler.events.expectEvent(), .opened)
        es.stop()
        XCTAssertEqual(mockHandler.events.expectEvent(), .closed)
    }

    func testLastEventIdUpdatedByEvents() {
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        config.reconnectTime = 0.1
        let es = EventSource(config: config)
        es.start()
        let handler = MockingProtocol.requested.expectEvent()
        handler.respond(statusCode: 200)
        XCTAssertEqual(mockHandler.events.expectEvent(), .opened)
        XCTAssertEqual(es.getLastEventId(), "")
        handler.respond(didLoad: "id: abc\n\n")
        // Comment used for synchronization
        handler.respond(didLoad: ":comment\n")
        XCTAssertEqual(mockHandler.events.expectEvent(), .comment("comment"))
        XCTAssertEqual(es.getLastEventId(), "abc")
        handler.finish()
        XCTAssertEqual(mockHandler.events.expectEvent(), .closed)
        // Expect to reconnect and include new event id
        let reconnectHandler = MockingProtocol.requested.expectEvent()
        XCTAssertEqual(reconnectHandler.request.allHTTPHeaderFields?["Last-Event-Id"], "abc")
        es.stop()
    }

    func testUsesRetryTime() {
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        // Long enough to cause a timeout if the retry time is not updated
        config.reconnectTime = 5
        let es = EventSource(config: config)
        es.start()
        let handler = MockingProtocol.requested.expectEvent()
        handler.respond(statusCode: 200)
        XCTAssertEqual(mockHandler.events.expectEvent(), .opened)
        handler.respond(didLoad: "retry: 100\n\n")
        handler.finish()
        XCTAssertEqual(mockHandler.events.expectEvent(), .closed)
        // Expect to reconnect before this times out
        _ = MockingProtocol.requested.expectEvent()
        es.stop()
    }

    func testCallsHandlerWithMessage() {
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        let es = EventSource(config: config)
        es.start()
        let handler = MockingProtocol.requested.expectEvent()
        handler.respond(statusCode: 200)
        XCTAssertEqual(mockHandler.events.expectEvent(), .opened)
        handler.respond(didLoad: "event: custom\ndata: {}\n\n")
        XCTAssertEqual(mockHandler.events.expectEvent(), .message("custom", MessageEvent(data: "{}")))
        es.stop()
        XCTAssertEqual(mockHandler.events.expectEvent(), .closed)
    }

    func testRetryOnInvalidResponseCode() {
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        config.reconnectTime = 0.1
        let es = EventSource(config: config)
        es.start()
        let handler = MockingProtocol.requested.expectEvent()
        handler.respond(statusCode: 400)
        guard case let .error(err) = mockHandler.events.expectEvent(),
              let responseErr = err as? UnsuccessfulResponseError
        else {
            XCTFail("Expected UnsuccessfulResponseError to be given to handler")
            return
        }
        XCTAssertEqual(responseErr.responseCode, 400)
        // Expect the client to reconnect
        _ = MockingProtocol.requested.expectEvent()
        es.stop()
    }

    func testShutdownByErrorHandlerOnInitialErrorResponse() {
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        config.reconnectTime = 0.1
        config.connectionErrorHandler = { err in
            if let responseErr = err as? UnsuccessfulResponseError {
                XCTAssertEqual(responseErr.responseCode, 400)
            } else {
                XCTFail("Expected UnsuccessfulResponseError to be given to handler")
            }
            return .shutdown
        }
        let es = EventSource(config: config)
        es.start()
        let handler = MockingProtocol.requested.expectEvent()
        handler.respond(statusCode: 400)
        // Expect the client not to reconnect
        MockingProtocol.requested.expectNoEvent(within: 1.0)
        es.stop()
        // Error should not have been given to the handler
        mockHandler.events.expectNoEvent()
    }

    func testShutdownByErrorHandlerOnResponseCompletionError() {
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        config.reconnectTime = 0.1
        config.connectionErrorHandler = { _ in
            .shutdown
        }
        let es = EventSource(config: config)
        es.start()
        let handler = MockingProtocol.requested.expectEvent()
        handler.respond(statusCode: 200)
        XCTAssertEqual(mockHandler.events.expectEvent(), .opened)
        handler.finishWith(error: DummyError())
        XCTAssertEqual(mockHandler.events.expectEvent(), .closed)
        // Expect the client not to reconnect
        MockingProtocol.requested.expectNoEvent(within: 1.0)
        es.stop()
        // Error should not have been given to the handler
        mockHandler.events.expectNoEvent()
    }
#endif
}

private class DummyError: Error { }
