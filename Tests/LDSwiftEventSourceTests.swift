import XCTest
@testable import LDSwiftEventSource

final class LDSwiftEventSourceTests: XCTestCase {
    func testConfigDefaults() {
        let url = URL(string: "abc")!
        let config = EventSource.Config(handler: MockHandler(), url: url)
        XCTAssertEqual(config.url, url)
        XCTAssertEqual(config.method, "GET")
        XCTAssertEqual(config.body, nil)
        XCTAssertEqual(config.lastEventId, nil)
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
        var config = EventSource.Config(handler: MockHandler(), url: url)

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
        var config = EventSource.Config(handler: MockHandler(), url: URL(string: "abc")!)
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
        var config = EventSource.Config(handler: MockHandler(), url: URL(string: "abc")!)
        var es = EventSource(config: config)
        XCTAssertEqual(es.getLastEventId(), nil)
        config.lastEventId = "def"
        es = EventSource(config: config)
        XCTAssertEqual(es.getLastEventId(), "def")
    }

    func testCreatedSession() {
        let config = EventSource.Config(handler: MockHandler(), url: URL(string: "abc")!)
        let session = EventSourceDelegate(config: config).createSession()
        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, config.idleTimeout)
        XCTAssertEqual(session.configuration.httpAdditionalHeaders?["Accept"] as? String, "text/event-stream")
        XCTAssertEqual(session.configuration.httpAdditionalHeaders?["Cache-Control"] as? String, "no-cache")
    }

    func testCreateRequest() {
        // 192.0.2.1 is assigned as TEST-NET-1 reserved usage.
        var config = EventSource.Config(handler: MockHandler(), url: URL(string: "http://192.0.2.1")!)
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
        let handler = MockHandler()
        var connectionErrorHandlerCallCount = 0
        var connectionErrorAction: ConnectionErrorAction = .proceed
        var config = EventSource.Config(handler: handler, url: URL(string: "abc")!)
        config.connectionErrorHandler = { error in
            connectionErrorHandlerCallCount += 1
            return connectionErrorAction
        }
        let es = EventSourceDelegate(config: config)
        XCTAssertEqual(es.dispatchError(error: DummyError()), .proceed)
        XCTAssertEqual(connectionErrorHandlerCallCount, 1)
        guard case .error(let err) = handler.takeEvent(), err is DummyError
        else {
            XCTFail("handler should receive error if EventSource is not shutting down")
            return
        }
        XCTAssertTrue(handler.receivedEvents.isEmpty)
        connectionErrorAction = .shutdown
        XCTAssertEqual(es.dispatchError(error: DummyError()), .shutdown)
        XCTAssertEqual(connectionErrorHandlerCallCount, 2)
        XCTAssertTrue(handler.receivedEvents.isEmpty)
    }
}

private enum ReceivedEvent: Equatable {
    case opened, closed, message(String, MessageEvent), comment(String), error(Error)

    static func == (lhs: ReceivedEvent, rhs: ReceivedEvent) -> Bool {
        switch (lhs, rhs) {
        case (.opened, .opened):
            return true
        case (.closed, .closed):
            return true
        case let (.message(typeLhs, eventLhs), .message(typeRhs, eventRhs)):
            return typeLhs == typeRhs && eventLhs == eventRhs
        case let (.comment(lhs), .comment(rhs)):
            return lhs == rhs
        case (.error, .error):
            return true
        default:
            return false
        }
    }
}

private class MockHandler: EventHandler {
    var receivedEvents: [ReceivedEvent] = []

    func onOpened() {
        receivedEvents.append(.opened)
    }

    func onClosed() {
        receivedEvents.append(.closed)
    }

    func onMessage(eventType: String, messageEvent: MessageEvent) {
        receivedEvents.append(.message(eventType, messageEvent))
    }

    func onComment(comment: String) {
        receivedEvents.append(.comment(comment))
    }

    func onError(error: Error) {
        receivedEvents.append(.error(error))
    }

    func takeEvent() -> ReceivedEvent {
        receivedEvents.remove(at: 0)
    }
}

private class DummyError: Error { }
