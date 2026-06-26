import Foundation
import Testing
@testable import LDSwiftEventSource

#if os(Linux) || os(Windows)
import FoundationNetworking
#endif

@Suite("LDSwiftEventSource", .serialized)
final class LDSwiftEventSourceTests {
    init() {
        #expect(URLProtocol.registerClass(MockingProtocol.self))
        MockingProtocol.resetRequested()
    }

    deinit {
        URLProtocol.unregisterClass(MockingProtocol.self)
    }

    // A throwaway continuation for tests that exercise the delegate directly and do not
    // observe the event stream.
    private func makeDelegate(_ config: EventSource.Config) -> EventSourceDelegate {
        let (_, continuation) = AsyncStream.makeStream(of: EventSourceEvent.self)
        return EventSourceDelegate(config: config, continuation: continuation)
    }

    @Test func configDefaults() {
        let url = URL(string: "abc")!
        let config = EventSource.Config(url: url)
        #expect(config.url == url)
        #expect(config.method == "GET")
        #expect(config.body == nil)
        #expect(config.lastEventId == "")
        #expect(config.headers == [:])
        #expect(config.reconnectTime == 1.0)
        #expect(config.maxReconnectTime == 30.0)
        #expect(config.backoffResetThreshold == 60.0)
        #expect(config.idleTimeout == 300.0)
        #expect(config.headerTransform(["abc": "123"]) == ["abc": "123"])
        #expect(config.connectionErrorHandler(DummyError()) == .proceed)
    }

    @Test func configModification() {
        let url = URL(string: "abc")!
        var config = EventSource.Config(url: url)

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

        #expect(config.url == url)
        #expect(config.method == "REPORT")
        #expect(config.body == testBody)
        #expect(config.lastEventId == "eventId")
        #expect(config.headers == testHeaders)
        #expect(config.headerTransform(config.headers) == [:])
        #expect(config.reconnectTime == 2.0)
        #expect(config.maxReconnectTime == 60.0)
        #expect(config.backoffResetThreshold == 120.0)
        #expect(config.idleTimeout == 180.0)
        #expect(config.connectionErrorHandler(DummyError()) == .shutdown)
    }

    @Test func configUrlSession() {
        var config = EventSource.Config(url: URL(string: "abc")!)
        let defaultSessionConfig = config.urlSessionConfiguration
        #expect(defaultSessionConfig.timeoutIntervalForRequest == 300.0)
        #expect(defaultSessionConfig.httpAdditionalHeaders?["Accept"] as? String == "text/event-stream")
        #expect(defaultSessionConfig.httpAdditionalHeaders?["Cache-Control"] as? String == "no-cache")
        // Configuration should return a fresh session configuration each retrieval
        #expect(defaultSessionConfig !== config.urlSessionConfiguration)
        // Updating idleTimeout should effect session config
        config.idleTimeout = 600.0
        #expect(config.urlSessionConfiguration.timeoutIntervalForRequest == 600.0)
        #expect(defaultSessionConfig.timeoutIntervalForRequest == 300.0)
        // Updating returned urlSessionConfiguration without setting should not update the Config until set
        let sessionConfig = config.urlSessionConfiguration
        sessionConfig.allowsCellularAccess = false
        #expect(config.urlSessionConfiguration.allowsCellularAccess)
        config.urlSessionConfiguration = sessionConfig
        #expect(!config.urlSessionConfiguration.allowsCellularAccess)
        #expect(sessionConfig !== config.urlSessionConfiguration)
    }

    @Test func lastEventIdFromConfig() {
        var config = EventSource.Config(url: URL(string: "abc")!)
        var es = EventSource(config: config)
        #expect(es.getLastEventId() == "")
        config.lastEventId = "def"
        es = EventSource(config: config)
        #expect(es.getLastEventId() == "def")
    }

    @Test func createdSession() {
        let config = EventSource.Config(url: URL(string: "abc")!)
        let session = makeDelegate(config).createSession()
        #expect(session.configuration.timeoutIntervalForRequest == config.idleTimeout)
        #expect(session.configuration.httpAdditionalHeaders?["Accept"] as? String == "text/event-stream")
        #expect(session.configuration.httpAdditionalHeaders?["Cache-Control"] as? String == "no-cache")
    }

    @Test func createRequest() {
        // 192.0.2.1 is assigned as TEST-NET-1 reserved usage.
        var config = EventSource.Config(url: URL(string: "http://192.0.2.1")!)
        // Testing default configs
        var request = makeDelegate(config).createRequest()
        #expect(request.url == config.url)
        #expect(request.httpMethod == config.method)
        #expect(request.httpBody == config.body)
        #expect(request.timeoutInterval == config.idleTimeout)
        #expect(request.allHTTPHeaderFields == config.headers)
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
            #expect(provided == ["removing": "a", "updating": "b", "Last-Event-Id": "eventId"])
            return overrideHeaders
        }
        request = makeDelegate(config).createRequest()
        #expect(request.url == config.url)
        #expect(request.httpMethod == config.method)
        #expect(request.httpBody == config.body)
        #expect(request.timeoutInterval == config.idleTimeout)
        #expect(request.allHTTPHeaderFields == overrideHeaders)
    }

    @Test func dispatchError() async {
        let connectionErrorHandlerCallCount = Box(0)
        let connectionErrorAction = Box<ConnectionErrorAction>(.proceed)
        var config = EventSource.Config(url: URL(string: "abc")!)
        config.connectionErrorHandler = { _ in
            connectionErrorHandlerCallCount.value += 1
            return connectionErrorAction.value
        }
        let (stream, continuation) = AsyncStream.makeStream(of: EventSourceEvent.self)
        let collector = EventCollector(stream)
        let es = EventSourceDelegate(config: config, continuation: continuation)
        #expect(es.dispatchError(error: DummyError()) == .proceed)
        #expect(connectionErrorHandlerCallCount.value == 1)
        guard case .error(let err)? = await collector.events.expectEvent(), err is DummyError
        else {
            Issue.record("handler should receive error if EventSource is not shutting down")
            return
        }
        await collector.events.expectNoEvent()
        connectionErrorAction.value = .shutdown
        #expect(es.dispatchError(error: DummyError()) == .shutdown)
        #expect(connectionErrorHandlerCallCount.value == 2)
        continuation.finish()
        collector.cancel()
    }

    func sessionWithMockProtocol() -> URLSessionConfiguration {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockingProtocol.self] + (sessionConfig.protocolClasses ?? [])
        return sessionConfig
    }

#if !os(Linux) && !os(Windows)
    @Test func startDefaultRequest() async throws {
        var config = EventSource.Config(url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        let es = EventSource(config: config)
        es.start()
        let handler = try #require(await MockingProtocol.requested.expectEvent())
        #expect(handler.request.url == config.url)
        #expect(handler.request.httpMethod == config.method)
        #expect(handler.request.httpBody == config.body)
        #expect(handler.request.timeoutInterval == config.idleTimeout)
        #expect(handler.request.allHTTPHeaderFields?["Accept"] == "text/event-stream")
        #expect(handler.request.allHTTPHeaderFields?["Cache-Control"] == "no-cache")
        #expect(handler.request.allHTTPHeaderFields?["Last-Event-Id"] == nil)
        es.stop()
    }

    @Test func startRequestWithConfiguration() async throws {
        var config = EventSource.Config(url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        config.method = "REPORT"
        config.body = Data("test body".utf8)
        config.idleTimeout = 500.0
        config.lastEventId = "abc"
        config.headers = ["X-LD-Header": "def"]
        let es = EventSource(config: config)
        es.start()
        let handler = try #require(await MockingProtocol.requested.expectEvent())
        #expect(handler.request.url == config.url)
        #expect(handler.request.httpMethod == config.method)
        #expect(handler.request.bodyStreamAsData() == config.body)
        #expect(handler.request.timeoutInterval == config.idleTimeout)
        #expect(handler.request.allHTTPHeaderFields?["Accept"] == "text/event-stream")
        #expect(handler.request.allHTTPHeaderFields?["Cache-Control"] == "no-cache")
        #expect(handler.request.allHTTPHeaderFields?["Last-Event-Id"] == config.lastEventId)
        #expect(handler.request.allHTTPHeaderFields?["X-LD-Header"] == "def")
        es.stop()
    }

    @Test func startRequestIsNotReentrant() async throws {
        var config = EventSource.Config(url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        let es = EventSource(config: config)
        es.start()
        es.start()
        _ = try #require(await MockingProtocol.requested.expectEvent())
        await MockingProtocol.requested.expectNoEvent()
        es.stop()
    }

    @Test func successfulResponseOpens() async throws {
        var config = EventSource.Config(url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        let es = EventSource(config: config)
        let collector = EventCollector(es.events)
        es.start()
        let handler = try #require(await MockingProtocol.requested.expectEvent())
        handler.respond(statusCode: 200)
        #expect(await collector.events.expectEvent() == .opened)
        es.stop()
        #expect(await collector.events.expectEvent() == .closed)
        collector.cancel()
    }

    @Test func lastEventIdUpdatedByEvents() async throws {
        var config = EventSource.Config(url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        config.reconnectTime = 0.1
        let es = EventSource(config: config)
        let collector = EventCollector(es.events)
        es.start()
        let handler = try #require(await MockingProtocol.requested.expectEvent())
        handler.respond(statusCode: 200)
        #expect(await collector.events.expectEvent() == .opened)
        #expect(es.getLastEventId() == "")
        handler.respond(didLoad: "id: abc\n\n")
        // Comment used for synchronization
        handler.respond(didLoad: ":comment\n")
        #expect(await collector.events.expectEvent() == .comment("comment"))
        #expect(es.getLastEventId() == "abc")
        handler.finish()
        #expect(await collector.events.expectEvent() == .closed)
        // Expect to reconnect and include new event id
        let reconnectHandler = try #require(await MockingProtocol.requested.expectEvent())
        #expect(reconnectHandler.request.allHTTPHeaderFields?["Last-Event-Id"] == "abc")
        es.stop()
        collector.cancel()
    }

    @Test func usesRetryTime() async throws {
        var config = EventSource.Config(url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        // Long enough to cause a timeout if the retry time is not updated
        config.reconnectTime = 5
        let es = EventSource(config: config)
        let collector = EventCollector(es.events)
        es.start()
        let handler = try #require(await MockingProtocol.requested.expectEvent())
        handler.respond(statusCode: 200)
        #expect(await collector.events.expectEvent() == .opened)
        handler.respond(didLoad: "retry: 100\n\n")
        handler.finish()
        #expect(await collector.events.expectEvent() == .closed)
        // Expect to reconnect before this times out
        _ = try #require(await MockingProtocol.requested.expectEvent())
        es.stop()
        collector.cancel()
    }

    @Test func callsHandlerWithMessage() async throws {
        var config = EventSource.Config(url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        let es = EventSource(config: config)
        let collector = EventCollector(es.events)
        es.start()
        let handler = try #require(await MockingProtocol.requested.expectEvent())
        handler.respond(statusCode: 200)
        #expect(await collector.events.expectEvent() == .opened)
        handler.respond(didLoad: "event: custom\ndata: {}\n\n")
        #expect(await collector.events.expectEvent() == .message("custom", MessageEvent(data: "{}")))
        es.stop()
        #expect(await collector.events.expectEvent() == .closed)
        collector.cancel()
    }

    @Test func retryOnInvalidResponseCode() async throws {
        var config = EventSource.Config(url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        config.reconnectTime = 0.1
        let es = EventSource(config: config)
        let collector = EventCollector(es.events)
        es.start()
        let handler = try #require(await MockingProtocol.requested.expectEvent())
        handler.respond(statusCode: 400)
        guard case .error(let err)? = await collector.events.expectEvent(),
              let responseErr = err as? UnsuccessfulResponseError
        else {
            Issue.record("Expected UnsuccessfulResponseError to be given to handler")
            return
        }
        #expect(responseErr.responseCode == 400)
        // Expect the client to reconnect
        _ = try #require(await MockingProtocol.requested.expectEvent())
        es.stop()
        collector.cancel()
    }

    @Test func shutdownByErrorHandlerOnInitialErrorResponse() async throws {
        // The connectionErrorHandler runs on the URLSession delegate queue, off the test's
        // task, so we capture what it observed and assert on the test thread.
        let observedResponseCode = Box<Int?>(nil)
        var config = EventSource.Config(url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        config.reconnectTime = 0.1
        config.connectionErrorHandler = { err in
            observedResponseCode.value = (err as? UnsuccessfulResponseError)?.responseCode
            return .shutdown
        }
        let es = EventSource(config: config)
        let collector = EventCollector(es.events)
        es.start()
        let handler = try #require(await MockingProtocol.requested.expectEvent())
        handler.respond(statusCode: 400)
        // Expect the client not to reconnect
        await MockingProtocol.requested.expectNoEvent(within: .seconds(1))
        es.stop()
        // Error should not have been delivered through the stream
        await collector.events.expectNoEvent()
        #expect(observedResponseCode.value == 400)
        collector.cancel()
    }

    @Test func shutdownByErrorHandlerOnResponseCompletionError() async throws {
        var config = EventSource.Config(url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        config.reconnectTime = 0.1
        config.connectionErrorHandler = { _ in
            .shutdown
        }
        let es = EventSource(config: config)
        let collector = EventCollector(es.events)
        es.start()
        let handler = try #require(await MockingProtocol.requested.expectEvent())
        handler.respond(statusCode: 200)
        #expect(await collector.events.expectEvent() == .opened)
        handler.finishWith(error: DummyError())
        #expect(await collector.events.expectEvent() == .closed)
        // Expect the client not to reconnect
        await MockingProtocol.requested.expectNoEvent(within: .seconds(1))
        es.stop()
        // Error should not have been delivered through the stream
        await collector.events.expectNoEvent()
        collector.cancel()
    }

    @Test func shutdownBy204Response() async throws {
        var config = EventSource.Config(url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        config.reconnectTime = 0.1

        let es = EventSource(config: config)
        let collector = EventCollector(es.events)
        es.start()

        let handler = try #require(await MockingProtocol.requested.expectEvent())
        handler.respond(statusCode: 204)

        await MockingProtocol.requested.expectNoEvent(within: .seconds(1))

        es.stop()
        // Error should not have been delivered through the stream
        await collector.events.expectNoEvent()
        collector.cancel()
    }

    @Test func canOverride204DefaultBehavior() async throws {
        // The connectionErrorHandler runs on the URLSession delegate queue, off the test's
        // task, so we capture what it observed and assert on the test thread.
        let observedResponseCode = Box<Int?>(nil)
        var config = EventSource.Config(url: URL(string: "http://example.com")!)
        config.urlSessionConfiguration = sessionWithMockProtocol()
        config.reconnectTime = 0.1
        config.connectionErrorHandler = { err in
            observedResponseCode.value = (err as? UnsuccessfulResponseError)?.responseCode
            return .shutdown
        }
        let es = EventSource(config: config)
        let collector = EventCollector(es.events)
        es.start()
        let handler = try #require(await MockingProtocol.requested.expectEvent())
        handler.respond(statusCode: 204)
        // Expect the client not to reconnect
        await MockingProtocol.requested.expectNoEvent(within: .seconds(1))
        es.stop()
        // Error should not have been delivered through the stream
        await collector.events.expectNoEvent()
        #expect(observedResponseCode.value == 204)
        collector.cancel()
    }
#endif
}

private struct DummyError: Error { }
