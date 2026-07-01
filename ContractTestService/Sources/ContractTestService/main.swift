import Dispatch
import Foundation
import Kitura
import LDSwiftEventSource

struct StatusResp: Encodable {
    let name = "swift-eventsource"
    let capabilities = ["server-directed-shutdown-request", "comments", "headers", "last-event-id", "post", "read-timeout", "report"]
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

let stateQueue = DispatchQueue(label: "StateQueue")
var nextId: Int = 0
var state: [String: EventSource] = [:]

let router = Router()

router.get("/") { _, resp, next in
    resp.send(StatusResp())
    next()
}

router.delete("/") { _, resp, next in
    resp.send(["message": "Shutting down contract test service"])
    next()
    Kitura.stop()
}

router.post("/") { req, resp, next in
    guard let createStreamReq = try? req.read(as: CreateStreamReq.self)
    else {
        resp.status(.badRequest).send(["message": "Body of POST to '/' invalid"])
        return next()
    }
    let es = EventSource(config: createStreamReq.createEventSourceConfig())
    let forwarder = CallbackForwarder(baseUrl: createStreamReq.callbackUrl)
    let stream = es.events
    let location: String = stateQueue.sync {
        state[String(nextId)] = es
        nextId += 1
        return "/control/\(nextId - 1)"
    }
    // The consumer task drains the stream until `es.stop()` finishes it.
    Task { await forwarder.consume(stream) }
    es.start()
    resp.headers["Location"] = location
    resp.send(["message": "Created test service entity at \(location)"])
    next()
}

router.delete("/control/:id") { req, resp, next in
    stateQueue.sync {
        if let es = state.removeValue(forKey: req.parameters["id"]!) {
            es.stop()
            resp.send(["message": "Shut down test service entity at \(req.matchedPath)"])
        } else {
            resp.status(.notFound).send(["message": "Test service entity not found at \(req.matchedPath)"])
        }
    }
    next()
}

Kitura.addHTTPServer(onPort: 8000, onAddress: "localhost", with: router)
Kitura.run()
