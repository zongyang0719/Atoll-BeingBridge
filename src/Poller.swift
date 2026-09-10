// 轮询。端点与判据全部照 being/touchbar/DESIGN.md 第三节。
//
// 渲染路径不联网：轮询在后台线程写 state，推帧的地方只读 state。
// 这条是 journal 09-05 定下的分层——网络一卡不该让刘海跟着冻。

import Foundation

/// 同步 HTTP。超时后回调仍可能晚到，所以结果放在带锁的盒子里——
/// 直接写捕获变量会和晚到的回调抢写，是个真实的数据竞争。
private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var code = -1
    private var obj: Any?
    func set(_ c: Int, _ o: Any?) { lock.lock(); code = c; obj = o; lock.unlock() }
    func get() -> (Int, Any?) { lock.lock(); defer { lock.unlock() }; return (code, obj) }
}

func httpJSON(_ url: URL, bearer: String? = nil, timeout: TimeInterval = 6) -> (code: Int, json: Any?) {
    var req = URLRequest(url: url, timeoutInterval: timeout)
    if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
    let box = Box()
    let sem = DispatchSemaphore(value: 0)
    let task = URLSession.shared.dataTask(with: req) { data, resp, _ in
        var o: Any? = nil
        if let data, !data.isEmpty { o = try? JSONSerialization.jsonObject(with: data) }
        box.set((resp as? HTTPURLResponse)?.statusCode ?? -1, o)
        sem.signal()
    }
    task.resume()
    if sem.wait(timeout: .now() + timeout + 2) == .timedOut { task.cancel() }
    return box.get()
}

final class BeingPoller {
    /// 读取路径而不是在启动时冻结凭证：Soul tab 保存一条新 URL 后，下一轮轮询就能接管，
    /// 不需要把用户踢出 Atoll、也不需要为了配置另开一个桌面 App。
    private let credentialsProvider: () -> BeingCredentials?
    private let offlineAfter: Int
    // 两个端点各记各的失败次数。原来共用一个计数器：活跃流每秒一次，
    // 连错 3 秒就判离线，比「连错三次」本来的意思激进得多；
    // 而流成功又会把 status 的失败清零，两边互相掩盖。
    private var statusFailures = 0
    private var lastConfigAt = Date.distantPast

    private let lock = NSLock()
    private var _state = BeingState()
    /// 轮询在自己的线程上写，推帧的线程读。结构体赋值不是原子的，必须加锁，
    /// 否则读到的可能是半新半旧的一份。
    private(set) var state: BeingState {
        get { lock.lock(); defer { lock.unlock() }; return _state }
        set { lock.lock(); _state = newValue; lock.unlock() }
    }
    private func mutate(_ f: (inout BeingState) -> Void) {
        lock.lock(); f(&_state); lock.unlock()
    }

    init(offlineAfter: Int, credentialsProvider: @escaping () -> BeingCredentials?) {
        self.credentialsProvider = credentialsProvider
        self.offlineAfter = offlineAfter
    }

    /// 一轮：活跃流每次都看；status 与 llm-config 5 秒一次。
    /// 原来是 30 秒——SBS 在 Loom 里一点就变，这边最多要等半分钟才跟上，不算实时。
    func tick() {
        guard let credentials = credentialsProvider() else {
            setNeedsSetup()
            return
        }
        let now = Date()
        if now.timeIntervalSince(lastConfigAt) > 5 {
            pollStatusAndConfig(credentials)
            lastConfigAt = now
        }
        pollStream(credentials)
    }

    private func pollStatusAndConfig(_ credentials: BeingCredentials) {
        guard let statusURL = credentials.endpoint("/api/status") else { return }
        let (code, json) = httpJSON(statusURL)
        guard code == 200, let o = json as? [String: Any], (o["status"] as? String) == "running" else {
            statusFailures += 1
            // 连错三次才判离线：那台机器网络抖得厉害，单次失败不能当离线（journal 09-05）。
            if statusFailures >= offlineAfter { mutate { $0.activity = .offline } }
            return
        }
        statusFailures = 0
        let reportedName = ((o["being_name"] as? String) ?? (o["name"] as? String))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        mutate {
            if let reportedName, !reportedName.isEmpty { $0.name = reportedName }
            if let m = o["model"] as? String { $0.model = m }
            if $0.activity == .offline { $0.activity = .idle }
        }

        guard let configURL = credentials.endpoint("/api/llm/config") else { return }
        let (c2, j2) = httpJSON(configURL)
        if c2 == 200, let o2 = j2 as? [String: Any] {
            mutate {
                if let v = o2["sbs_enabled"] as? Bool { $0.sbsEnabled = v }
                if let t = o2["thinking"] as? String { $0.thinkingDepth = t }
                if let m = o2["model"] as? String { $0.model = m }
            }
        }
    }

    private func pollStream(_ credentials: BeingCredentials) {
        guard let streamURL = credentials.endpoint("/api/stream/active") else { return }
        let (code, json) = httpJSON(streamURL)

        // 空闲时服务端返回 204 空响应，不是文档写的 finished:true——
        // 第一版把它当失败，把「安静」误判成「离线」（journal 09-05）。
        // 204 本身就证明服务端活着，所以它也要能把「离线」解除——
        // 原来写成「离线时忽略 204」，一旦误判离线就得等下一轮 status 才恢复。
        if code == 204 {
            statusFailures = 0
            setIdle()
            return
        }
        // 活跃流失败不判离线，那是 status 的职责；这里只是这一轮没拿到，保持上一次的状态。
        guard code == 200, let o = json as? [String: Any] else { return }
        statusFailures = 0

        let finished = o["finished"] as? Bool ?? true
        let events = o["events"] as? [[String: Any]] ?? []
        if finished || events.isEmpty { setIdle(); return }

        let trigger = (o["trigger_message"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let startedAt = (o["started_at"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }

        // 取最后一个「有意义」的事件。usage 是纯用量记账，不代表在干什么，跳过
        // ——DESIGN.md 和 loom 的 shell 脚本都是这么做的。
        let meaningful = events.reversed().first {
            ($0["event"] as? String).map { $0 != "usage" } ?? false
        }
        let kind = meaningful?["event"] as? String ?? ""
        let act: Activity
        let detail: String
        switch kind {
        case "thinking", "reasoning":
            act = .thinking; detail = "在思考"
        case "tool_use", "tool_result":
            act = .working; detail = loomToolLabel(meaningful)
        case "content_block_delta", "text":
            act = .replying; detail = "在回复"
        case "message_stop":
            setIdle(); return
        default:
            act = .thinking; detail = "在思考"
        }
        mutate {
            $0.activity = act
            $0.activityDetail = detail
            $0.trigger = trigger
            $0.streamStartedAt = startedAt
        }
    }

    private func setIdle() {
        mutate {
            $0.activity = .idle
            $0.activityDetail = ""
            $0.trigger = ""
            $0.streamStartedAt = nil
        }
    }

    private func setNeedsSetup() {
        mutate {
            $0.name = "Being"
            $0.activity = .setup
            $0.model = ""
            $0.activityDetail = ""
            $0.trigger = ""
            $0.streamStartedAt = nil
        }
    }

    /// 只把工具名映射成 Loom 已使用的状态词，不把参数、网页内容或思维链推到闭合刘海。
    private func loomToolLabel(_ event: [String: Any]?) -> String {
        let data = event?["data"] as? [String: Any]
        let name = ((data?["name"] as? String) ?? (data?["tool_name"] as? String) ?? "").lowercased()
        if name.contains("search") || name.contains("lookup") || name.contains("query") { return "在搜索" }
        if name.contains("browse") || name.contains("fetch") || name.contains("web") { return "在浏览" }
        if name.contains("read") || name.contains("open") || name.contains("inspect") { return "在阅读" }
        if name.contains("write") || name.contains("edit") || name.contains("patch") { return "在编写" }
        if name.contains("run") || name.contains("exec") || name.contains("shell") || name.contains("terminal") { return "在执行" }
        return "在行动"
    }
}
