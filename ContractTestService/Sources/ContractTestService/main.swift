import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HTTPTypes
import Hummingbird
import LDSwiftEventSource
import Logging
import ServiceLifecycle

struct StatusResp: ResponseEncodable {
    let name = "swift-eventsource"
    let capabilities = ["server-directed-shutdown-request", "comments", "headers", "last-event-id", "post", "read-timeout", "report"]
}

struct MessageResponse: ResponseEncodable {
    let message: String
}

struct CreateStreamReq: Decodable {
    let streamUrl: URL
    let callbackUrl: URL
    let initialDelayMs: Int?
    let readTimeoutMs: Int?
    let lastEventId: String?
    let headers: [String: String]?
    let method: String?
    let body: String?

    func createEventSourceConfig() -> EventSource.Config {
        var esConfig = EventSource.Config(url: streamUrl)
        if let initialDelayMs = initialDelayMs { esConfig.reconnectTime = Double(initialDelayMs) / 1000.0 }
        if let readTimeoutMs = readTimeoutMs { esConfig.idleTimeout = Double(readTimeoutMs) / 1000.0 }
        if let lastEventId = lastEventId { esConfig.lastEventId = lastEventId }
        if let headers = headers { esConfig.headers = headers }
        if let method = method { esConfig.method = method }
        if let body = body { esConfig.body = Data(body.utf8) }
        return esConfig
    }
}

// Consumes an `EventSource`'s event stream and forwards each event to the test harness's
// callback URL as a numbered POST, per the SSE contract-test protocol.
struct CallbackForwarder: Sendable {
    struct EventPayloadEvent: Encodable {
        let type: String
        let data: String
        let id: String?
    }

    struct EventPayload: Encodable {
        let kind = "event"
        let event: EventPayloadEvent
    }

    struct CommentPayload: Encodable {
        let kind = "comment"
        let comment: String
    }

    struct ErrorPayload: Encodable {
        let kind = "error"
    }

    let baseUrl: URL

    func consume(_ stream: AsyncStream<EventSourceEvent>) async {
        var count = 0
        for await event in stream {
            switch event {
            case .opened, .closed:
                continue
            case let .message(eventType, msg):
                count += 1
                sendUpdate(count, EventPayload(event: EventPayloadEvent(type: eventType, data: msg.data, id: msg.lastEventId)))
            case let .comment(comment):
                count += 1
                sendUpdate(count, CommentPayload(comment: comment))
            case .error:
                count += 1
                sendUpdate(count, ErrorPayload())
            }
        }
    }

    func sendUpdate<T: Encodable>(_ count: Int, _ update: T) {
        var request = URLRequest(url: baseUrl.appendingPathComponent(String(count), isDirectory: false))
        request.httpMethod = "POST"
        let data = try! JSONEncoder().encode(update)
        URLSession.shared.uploadTask(with: request, from: data) { _, _, _ in }.resume()
    }
}

// Tracks the active `EventSource` streams by their control-path id. `EventSource` is Sendable,
// so an actor gives race-free access from the concurrent request handlers.
actor StreamStore {
    private var nextId = 0
    private var streams: [String: EventSource] = [:]

    func add(_ es: EventSource) -> String {
        let id = String(nextId)
        nextId += 1
        streams[id] = es
        return "/control/\(id)"
    }

    func remove(id: String) -> EventSource? {
        streams.removeValue(forKey: id)
    }
}

// Lets the `DELETE /` route stop the running service. The trigger is installed once the
// service group exists (after the routes are declared), so it is set behind a lock.
final class ShutdownHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () async -> Void)?

    func set(_ handler: @escaping @Sendable () async -> Void) {
        lock.withLock { self.handler = handler }
    }

    func fire() async {
        let handler = lock.withLock { self.handler }
        await handler?()
    }
}

let store = StreamStore()
let shutdown = ShutdownHandle()

let router = Router()

router.get("/") { _, _ in
    StatusResp()
}

router.delete("/") { _, _ in
    // Stop the service once this response has been written; graceful shutdown drains the
    // in-flight request first.
    Task { await shutdown.fire() }
    return MessageResponse(message: "Shutting down contract test service")
}

router.post("/") { request, context -> Response in
    let createStreamReq = try await request.decode(as: CreateStreamReq.self, context: context)
    let es = EventSource(config: createStreamReq.createEventSourceConfig())
    let forwarder = CallbackForwarder(baseUrl: createStreamReq.callbackUrl)
    let location = await store.add(es)
    // The consumer task drains the stream until `es.stop()` finishes it.
    Task { await forwarder.consume(es.events) }
    es.start()
    var response = try MessageResponse(message: "Created test service entity at \(location)")
        .response(from: request, context: context)
    response.headers[.location] = location
    return response
}

router.delete("/control/:id") { _, context -> MessageResponse in
    guard let id = context.parameters.get("id"), let es = await store.remove(id: id) else {
        throw HTTPError(.notFound, message: "Test service entity not found")
    }
    es.stop()
    return MessageResponse(message: "Shut down test service entity at /control/\(id)")
}

let app = Application(
    router: router,
    configuration: .init(address: .hostname("127.0.0.1", port: 8000))
)

let serviceGroup = ServiceGroup(
    configuration: .init(
        services: [app],
        gracefulShutdownSignals: [.sigterm, .sigint],
        logger: Logger(label: "contract-test-service")
    )
)
shutdown.set { await serviceGroup.triggerGracefulShutdown() }
try await serviceGroup.run()
