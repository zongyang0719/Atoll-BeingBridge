// 本机小服务。存在的唯一理由：让刘海里那张网页拿到数据、发得出消息，
// 而 **token 不进推给 Atoll 的 payload**——页面只跟 127.0.0.1 说话，
// 鉴权由这里补上，密钥仍然只住仅当前用户可读的本机文件。
//
// 附带好处：页面自己取数据，daemon 就不用为了更新状态去重推 webContent。
// 重推会让 WKWebView 重新加载，正在输入的字会全没
// （`ExtensionWebContentView.updateNSView` 只在 HTML 变了才 reload）。

import Foundation
import Network

final class LocalServer {
    private let port: NWEndpoint.Port
    /// 每次 daemon 启动生成的本机 setup key。它不是 Being 密钥，只用于让任意网页
    /// 不能伪造设置请求；只有 Atoll 当前渲染的 Soul 页面会拿到它。
    let setupKey = UUID().uuidString
    /// 不在启动时冻结凭证。这样首次打开 Soul tab 就能配置，保存后本机服务立即改用新 URL。
    private let credentialsProvider: () -> BeingCredentials?
    private let being: BeingPoller
    private var listener: NWListener?
    /// 一条 `/send` 是可能持续数分钟的 SSE。NWConnection 不会替我们保留
    /// URLSession 的 delegate，所以 relay 必须由 server 强持有直到流结束。
    private let relayLock = NSLock()
    private var relays: [UUID: StreamRelay] = [:]
    /// 草稿属于当前 Soul 会话，但不属于一次 WKWebView 实例：hover 收起后重新
    /// 创建页面时仍可恢复。只留在这个回环 daemon 的内存中，不进 Being、不上网。
    private let draft = DraftBox()
    /// 对话场景属于 Being 名称而不是 URL 或 token。它让 Atoll、Desktop、Workbench
    /// 各自有独立上下文，同时仍允许 Loom 兼容旧的无 scene 消息。
    private let scene = SceneBox()

    init?(port: UInt16, credentialsProvider: @escaping () -> BeingCredentials?, being: BeingPoller) {
        guard let p = NWEndpoint.Port(rawValue: port) else { return nil }
        self.port = p
        self.credentialsProvider = credentialsProvider
        self.being = being
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // 只监听回环。别的机器连不上，也就不需要再加一层鉴权。
        // 注意：requiredLocalEndpoint 已经带了端口，再传 `on: port` 会 EINVAL(22)。
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)
        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.start(queue: .global(qos: .utility))
        listener = l
    }

    private func accept(_ c: NWConnection) {
        c.start(queue: .global(qos: .utility))
        receive(c, buffer: Data())
    }

    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, err in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if err != nil { c.cancel(); return }

            // 等到头部收全；有 body 的话再等够 Content-Length。
            guard let headEnd = buf.range(of: Data("\r\n\r\n".utf8)) else {
                if done { c.cancel() } else { self.receive(c, buffer: buf) }
                return
            }
            let head = String(decoding: buf[..<headEnd.lowerBound], as: UTF8.self)
            let length = head.split(separator: "\r\n")
                .first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
            let body = buf[headEnd.upperBound...]
            if body.count < length {
                if done { c.cancel() } else { self.receive(c, buffer: buf) }
                return
            }
            self.handle(head: head, body: Data(body.prefix(length)), on: c)
        }
    }

    private func handle(head: String, body: Data, on c: NWConnection) {
        let line = head.split(separator: "\r\n").first.map(String.init) ?? ""
        let parts = line.split(separator: " ")
        let method = parts.first.map(String.init) ?? ""
        let path = parts.count > 1 ? String(parts[1]) : "/"

        if method == "OPTIONS" { return send(c, 204, Data(), type: "text/plain") }

        let route = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        if route == "/settings" || route == "/settings/test" {
            guard hasSetupKey(head) else {
                return send(c, 403, json(["error": "设置请求未获授权。"]), type: "application/json")
            }
        }
        switch (method, route) {
        case ("GET", "/state"):
            send(c, 200, stateJSON(), type: "application/json")
        case ("GET", "/settings"):
            // 故意不返回 URL、token 或 host。网页只需要知道是否已配置，不能借此读密钥。
            send(c, 200, settingsJSON(), type: "application/json")
        case ("POST", "/settings/test"):
            guard let raw = requestedBeingURL(from: body) else {
                return send(c, 400, json(["error": "请输入完整 Being URL。"]), type: "application/json")
            }
            switch verifyBeingURL(raw) {
            case .success(let name):
                send(c, 200, json(["name": name]), type: "application/json")
            case .failure(let message):
                send(c, 400, json(["error": message]), type: "application/json")
            }
        case ("PUT", "/settings"):
            guard let raw = requestedBeingURL(from: body) else {
                return send(c, 400, json(["error": "请输入完整 Being URL。"]), type: "application/json")
            }
            switch verifyBeingURL(raw) {
            case .success(let name):
                do {
                    try Config.saveBeingURL(raw)
                    Config.load().write() // 只留下非敏感字段，并清理旧配置中的历史字段。
                    let sceneID = atollSceneID(for: name)
                    scene.set(sceneID)
                    var response: [String: Any] = ["name": name]
                    if let sceneID { response["scene_id"] = sceneID }
                    send(c, 200, json(response), type: "application/json")
                } catch {
                    send(c, 500, json(["error": "无法保存设置。"]), type: "application/json")
                }
            case .failure(let message):
                send(c, 400, json(["error": message]), type: "application/json")
            }
        case ("GET", "/history"):
            // 其他 Loom scene 也会写进同一份 history；多取一点后由页面按 scene
            // 过滤，才不会因为最近的 Desktop / Workbench 消息把 Atoll 的上下文挤掉。
            let (_, data) = proxy("/api/history?limit=100", method: "GET", body: nil)
            send(c, 200, data ?? Data("[]".utf8), type: "application/json")
        case ("GET", "/draft"):
            send(c, 200, draftJSON(), type: "application/json")
        case ("PUT", "/draft"):
            let request = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            guard let text = request?["draft"] as? String, text.count <= 8_000 else {
                return send(c, 400, Data("{}".utf8), type: "application/json")
            }
            draft.set(text)
            send(c, 204, Data(), type: "application/json")
        case ("GET", "/active"):
            // `after` 只认正整数。网页拿它读 Loom 的 replay buffer，既能补 202
            // 的异步请求，也能在网页重载后接上本轮，不需要把 token 交给 WKWebView。
            let components = URLComponents(string: "http://localhost\(path)")
            let after = components?.queryItems?.first(where: { $0.name == "after" })?.value
                .flatMap(Int.init).flatMap { $0 >= 0 ? $0 : nil }
            let upstream = after.map { "/api/stream/active?after=\($0)" } ?? "/api/stream/active"
            let (code, data) = proxy(upstream, method: "GET", body: nil)
            send(c, code == 204 ? 204 : (code == 200 ? 200 : 502), data ?? Data(), type: "application/json")
        case ("POST", "/send"):
            let request = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            let text = request?["message"] as? String ?? ""
            let sessionID = request?["session_id"] as? String
            guard !text.isEmpty else { return send(c, 400, Data("{}".utf8), type: "application/json") }
            // 页面带来的 scene_id 只用于它自己的筛选；上游标签由 daemon 从已验证
            // 的 Being 名称决定，不能由 WebView 任意指定。
            guard let sceneID = resolvedSceneID() else {
                return send(c, 503, json(["error": "暂时无法确认 Being 名称，请稍后重试。"]), type: "application/json")
            }
            streamMessage(text, sessionID: sessionID, sceneID: sceneID, on: c)
        default:
            send(c, 404, Data("{}".utf8), type: "application/json")
        }
    }

    private func send(_ c: NWConnection, _ code: Int, _ body: Data, type: String) {
        // 页面是 loadHTMLString 出来的，origin 是 null，所以必须放开跨域。
        let head = """
        HTTP/1.1 \(code) OK\r
        Content-Type: \(type); charset=utf-8\r
        Content-Length: \(body.count)\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Headers: Content-Type, X-Being-Notch-Setup\r
        Access-Control-Allow-Methods: GET, POST, PUT, OPTIONS\r
        Cache-Control: no-store\r
        Connection: close\r
        \r\n
        """
        c.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in c.cancel() })
    }

    private func hasSetupKey(_ head: String) -> Bool {
        let key = "x-being-notch-setup:"
        return head.split(separator: "\r\n").contains { line in
            let lowercased = line.lowercased()
            guard lowercased.hasPrefix(key) else { return false }
            return line.dropFirst(key.count).trimmingCharacters(in: .whitespaces) == setupKey
        }
    }

    /// 打开一个本地 SSE：上游若立即回流，就原样转给网页；若回 202，则转成一帧
    /// `meta.accepted`，由网页改读 `/active?after=` 的 replay buffer。这个分支就是
    /// BeingAnywhere 的关键处理，不能把 202 误作“没有回复”。
    private func streamMessage(_ text: String, sessionID: String?, sceneID: String?, on c: NWConnection) {
        var payload: [String: Any]
        if let sessionID, !sessionID.isEmpty {
            payload = ["message": text, "session_id": String(sessionID.prefix(512))]
        } else {
            payload = ["message": text]
        }
        if let sceneID {
            payload["scene_id"] = sceneID
            payload["scene_meta"] = [
                "client": "atoll-being-bridge",
                "scene_label": "Atoll",
            ]
        }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return send(c, 400, Data("{}".utf8), type: "application/json")
        }
        guard let credentials = credentialsProvider(),
              let url = credentials.endpoint("/api/chat/stream") else {
            return send(c, 502, Data("{}".utf8), type: "application/json")
        }
        var request = URLRequest(url: url, timeoutInterval: 125)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let id = UUID()
        let relay = StreamRelay(connection: c, request: request) { [weak self] in
            self?.relayLock.lock()
            self?.relays.removeValue(forKey: id)
            self?.relayLock.unlock()
        }
        relayLock.lock()
        relays[id] = relay
        relayLock.unlock()
        relay.start()
    }

    // MARK: Soul tab 内的设置

    private enum URLVerification {
        case success(String)
        case failure(String)
    }

    private func requestedBeingURL(from body: Data) -> String? {
        let request = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        guard let raw = request?["url"] as? String, raw.utf8.count <= 4_096 else { return nil }
        return raw
    }

    private func reportedName(fromStatus data: Data?) -> String? {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let name = ((object["being_name"] as? String) ?? (object["name"] as? String))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (name?.isEmpty == false) ? name : nil
    }

    private func knownSceneID() -> String? {
        if let existing = scene.get() { return existing }
        if let id = atollSceneID(for: being.state.name) {
            scene.set(id)
            return id
        }
        return nil
    }

    /// 正常运行时 poller 已经从 /api/status 拿到名称；刚启动的极短窗口则补一次
    /// 同一接口，确保第一条消息也不会漏掉 scene 标签。只在发送路径联网，避免
    /// `/state` 与 `/settings` 因网络暂时不可用拖慢面板的打开。
    private func resolvedSceneID() -> String? {
        if let existing = knownSceneID() { return existing }
        guard let credentials = credentialsProvider() else { return nil }
        let (code, data) = proxy(credentials, "/api/status", method: "GET", body: nil, timeout: 10)
        guard code == 200,
              let name = reportedName(fromStatus: data),
              let id = atollSceneID(for: name) else { return nil }
        scene.set(id)
        return id
    }

    /// 设置页把一条 URL 交给本机 daemon 验证；token 只在这个函数和上游请求里短暂存在，
    /// 不进 Atoll descriptor、日志或设置接口的响应体。
    private func verifyBeingURL(_ raw: String) -> URLVerification {
        let credentials: BeingCredentials
        do {
            credentials = try Config.credentials(fromBeingURL: raw)
        } catch {
            return .failure(error.localizedDescription)
        }
        let (code, data) = proxy(credentials, "/api/status", method: "GET", body: nil, timeout: 10)
        guard code == 200,
              let name = reportedName(fromStatus: data) else {
            return .failure("无法验证这条 URL，请检查地址和 token。")
        }
        return .success(name)
    }

    // MARK: 数据

    private func stateJSON() -> Data {
        let b = being.state
        var o: [String: Any] = [
            "name": b.name,
            "status": b.activity.label,
            "dot": b.dotClass,
            "color": b.dotHex,
            "trigger": b.trigger,
        ]
        if let sceneID = knownSceneID() { o["scene_id"] = sceneID }
        return (try? JSONSerialization.data(withJSONObject: o)) ?? Data("{}".utf8)
    }

    private func settingsJSON() -> Data {
        let configured = credentialsProvider() != nil
        var object: [String: Any] = ["configured": configured]
        if configured, being.state.activity != .setup { object["name"] = being.state.name }
        if let sceneID = knownSceneID() { object["scene_id"] = sceneID }
        return json(object)
    }

    private func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    }

    private func draftJSON() -> Data {
        (try? JSONSerialization.data(withJSONObject: ["draft": draft.get()])) ?? Data("{}".utf8)
    }

    /// 往 Being 转发，token 在这里补。页面永远看不到它。
    private func proxy(_ path: String, method: String, body: Data?) -> (Int, Data?) {
        guard let credentials = credentialsProvider() else { return (-1, nil) }
        return proxy(credentials, path, method: method, body: body, timeout: 120)
    }

    private func proxy(_ credentials: BeingCredentials, _ path: String, method: String,
                       body: Data?, timeout: TimeInterval) -> (Int, Data?) {
        guard let url = credentials.endpoint(path) else { return (-1, nil) }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let box = ProxyBox()
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { d, r, _ in
            box.set((r as? HTTPURLResponse)?.statusCode ?? -1, d)
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + timeout + 5)
        return box.get()
    }

}

private final class ProxyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var code = -1
    private var data: Data?
    func set(_ c: Int, _ d: Data?) { lock.lock(); code = c; data = d; lock.unlock() }
    func get() -> (Int, Data?) { lock.lock(); defer { lock.unlock() }; return (code, data) }
}

private final class DraftBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""

    func set(_ value: String) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func get() -> String {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class SceneBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func set(_ value: String?) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func get() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// 上游 SSE 到刘海 WKWebView 的最小转发器。请求和 token 都留在本机，网页只收到
/// 事件正文；不缓冲整段回复，避免原来的“等 message_stop 才显示一整块文字”。
private final class StreamRelay: NSObject, URLSessionDataDelegate {
    private let connection: NWConnection
    private let request: URLRequest
    private let onFinish: () -> Void
    private var session: URLSession?
    private var sentHeader = false
    private var closed = false
    private let lock = NSLock()

    init(connection: NWConnection, request: URLRequest, onFinish: @escaping () -> Void) {
        self.connection = connection
        self.request = request
        self.onFinish = onFinish
    }

    func start() {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: queue)
        self.session = session
        session.dataTask(with: request).resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 502
        sendHeader()
        if code == 202 {
            sendEvent("meta", ["accepted": true])
            completionHandler(.cancel)
        } else if (200..<300).contains(code) {
            completionHandler(.allow)
        } else {
            sendEvent("error", ["message": "Being 暂时无法接收这条消息。"])
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // 200 的数据已经是标准 SSE 帧，保持原样，浏览器会按 event/data 边界解析。
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil && !sentHeader {
            sendHeader()
            sendEvent("error", ["message": "连接 Being 时中断。"])
        }
        close()
    }

    private func sendHeader() {
        lock.lock()
        guard !sentHeader else { lock.unlock(); return }
        sentHeader = true
        lock.unlock()
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: text/event-stream; charset=utf-8\r
        Cache-Control: no-cache, no-store\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Headers: Content-Type\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Connection: close\r
        \r\n
        """
        connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in })
    }

    private func sendEvent(_ type: String, _ body: [String: Any]) {
        let json = (try? JSONSerialization.data(withJSONObject: body)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let frame = "event: \(type)\r\ndata: \(json)\r\n\r\n"
        connection.send(content: Data(frame.utf8), completion: .contentProcessed { _ in })
    }

    private func close() {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        closed = true
        lock.unlock()
        // 先排空 header / SSE，浏览器读到 EOF 后才完成本轮；直接 cancel 会丢末帧。
        connection.send(content: nil, completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            self.connection.cancel()
            self.session?.invalidateAndCancel()
            self.onFinish()
        })
    }
}
