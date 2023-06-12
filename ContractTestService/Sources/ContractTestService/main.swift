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
        var esConfig = EventSource.Config(handler: CallbackHandler(baseUrl: callbackUrl), url: streamUrl)
        if let initialDelayMs = initialDelayMs { esConfig.reconnectTime = Double(initialDelayMs) / 1000.0 }
        if let readTimeoutMs = readTimeoutMs { esConfig.idleTimeout = Double(readTimeoutMs) / 1000.0 }
        if let lastEventId = lastEventId { esConfig.lastEventId = lastEventId }
        if let headers = headers { esConfig.headers = headers }
        if let method = method { esConfig.method = method }
        if let body = body { esConfig.body = Data(body.utf8) }
        return esConfig
    }
}

class CallbackHandler: EventHandler {
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
    var count = 0

    init(baseUrl: URL) {
        self.baseUrl = baseUrl
    }

    func onOpened() { }
    func onClosed() { }

    func sendUpdate<T: Encodable>(_ update: T) {
        count += 1
        var request = URLRequest(url: baseUrl.appendingPathComponent(String(count), isDirectory: false))
        request.httpMethod = "POST"
        let data = try! JSONEncoder().encode(update)
        URLSession.shared.uploadTask(with: request, from: data) { _, _, _ in }.resume()
    }

    func onMessage(eventType type: String, messageEvent msg: MessageEvent) {
        sendUpdate(EventPayload(event: EventPayloadEvent(type: type, data: msg.data, id: msg.lastEventId)))
    }

    func onComment(comment: String) {
        sendUpdate(CommentPayload(comment: comment))
    }

    func onError(error: Error) {
        sendUpdate(ErrorPayload())
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
    let location: String = stateQueue.sync {
        state[String(nextId)] = es
        nextId += 1
        return "/control/\(nextId - 1)"
    }
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
