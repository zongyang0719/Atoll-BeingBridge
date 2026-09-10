// being-notch —— 一个 bridge 同时管两个面：跃迁药丸（live activity）和常驻标签（notch experience）。
//
// 自包含：自己轮询 being 服务端，不依赖别的进程。
// 配置见 ~/.being-notch/config.json；密钥不进配置文件。
//
// 二进制别放 ~/Documents —— 那是 TCC 保护目录，launchd 拉起的进程会静默卡在 dyld 的 open()。

import Foundation

let bundleID = "io.github.beingnotch.bridge"
let appName = "Being Notch"
let notchID = "being.status.notch"
let pillID = "being.status.pill"
let repesentAfter: TimeInterval = 5 * 3600   // durationHint 是 6 小时，到点前重推

func log(_ s: String) {
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
    print("\(f.string(from: Date()))  \(s)")
    fflush(stdout)
}

let config = Config.load()
let credentialsProvider: () -> BeingCredentials? = {
    guard let raw = Config.storedBeingURL() else { return nil }
    return try? Config.credentials(fromBeingURL: raw)
}
let being = BeingPoller(offlineAfter: config.offlineAfterFailures, credentialsProvider: credentialsProvider)

final class Bridge {
    private let setupKey: String?
    private var task: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var authorized = false
    private var seq = 0
    private var backoff: TimeInterval = 1
    private let queue = DispatchQueue(label: "being-notch.bridge")

    private var notchPresentedAt: Date?
    private var lastNotch: BeingState?
    private var pillUp = false
    private var lastPillTitle = ""

    init(setupKey: String?) {
        self.setupKey = setupKey
    }

    private func nextID() -> String { seq += 1; return "bn-\(seq)" }   // id 必须是字符串，发数字直接 -32700

    func start() {
        log("being-notch 启动，pid=\(ProcessInfo.processInfo.processIdentifier)")
        queue.async { self.connect() }
    }

    private func connect() {
        log("atoll: 连接 ws://127.0.0.1:9020")
        task = session.webSocketTask(with: URL(string: "ws://127.0.0.1:9020")!)
        task?.resume()
        receive()
        authorized = false
        notchPresentedAt = nil
        lastNotch = nil
        pillUp = false
        send(["jsonrpc": "2.0", "id": nextID(), "method": "atoll.requestAuthorization",
              "params": ["bundleIdentifier": bundleID, "appName": appName,
                         "scopes": ["notchExperiences", "liveActivities"]]])
    }

    private func reconnect(reason: String) {
        task?.cancel(with: .goingAway, reason: nil); task = nil
        let wait = backoff; backoff = min(backoff * 2, 30)
        log("atoll: \(reason)，\(Int(wait))s 后重连")
        queue.asyncAfter(deadline: .now() + wait) { [weak self] in self?.connect() }
    }

    private func send(_ obj: [String: Any]) {
        guard let task, let d = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: d, encoding: .utf8) else { return }
        let method = obj["method"] as? String ?? "unknown"
        task.send(.string(s)) { [weak self] err in
            guard let err else { return }
            self?.queue.async {
                self?.reconnect(reason: "发送 \(method) 失败：\(err.localizedDescription)")
            }
        }
    }

    private func receive() {
        task?.receive { [weak self] r in
            guard let self else { return }
            switch r {
            case .failure(let err):
                self.queue.async {
                    self.reconnect(reason: "接收失败：\(err.localizedDescription)")
                }
            case .success(let m):
                if case .string(let s) = m { self.queue.async { self.handle(s) } }
                self.receive()
            }
        }
    }

    private func handle(_ raw: String) {
        guard let d = raw.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        if let err = o["error"] as? [String: Any] {
            // 最常见的是 descriptor 校验没过。原样打出来，别让它静默失败。
            log("atoll: 被拒 \(err)")
            return
        }
        if let r = o["result"] as? [String: Any], let ok = r["authorized"] as? Bool {
            authorized = ok; backoff = 1
            log("atoll: connected, authorized=\(ok)")
            if ok { dismissLegacy(); pushNotch(force: true); syncPill() }
        }
    }

    // 换过 id 的旧标签会一直留在 Atoll 里（durationHint 6 小时），
    // 启动时按名字撤一遍，否则刘海里会多出一个不再更新的僵尸标签。
    private let legacyNotchIDs = ["being.soul.status"]

    private func dismissLegacy() {
        for eid in legacyNotchIDs {
            send(["jsonrpc": "2.0", "id": nextID(), "method": "atoll.dismissNotchExperience",
                  "params": ["experienceID": eid, "bundleIdentifier": bundleID]])
        }
    }

    // MARK: 推

    func tick() { queue.async { self.pushNotch(force: false); self.syncPill() } }

    private func pushNotch(force: Bool) {
        guard authorized else { return }
        let b = being.state
        if let at = notchPresentedAt, Date().timeIntervalSince(at) > repesentAfter {
            return doPushNotch(b, present: true)
        }
        if !force, let last = lastNotch, last == b { return }
        doPushNotch(b, present: force || lastNotch == nil)
    }

    private func doPushNotch(_ b: BeingState, present: Bool) {
        let d = notchDescriptor(b, chatPort: config.enableChat ? config.localPort : nil,
                                chatHeight: config.chatWebHeight, setupKey: setupKey,
                                id: notchID, bundleID: bundleID)
        send(["jsonrpc": "2.0", "id": nextID(),
              "method": present ? "atoll.presentNotchExperience" : "atoll.updateNotchExperience",
              "params": ["descriptor": d]])
        if present { notchPresentedAt = Date() }
        lastNotch = b
        log("\(present ? "present" : "update") notch · \(b.name) \(b.activity.label)")
    }

    /// 药丸只在真的在动时挂着；安静就撤掉，别跟常驻标签重复。
    private func syncPill() {
        guard authorized else { return }
        let b = being.state
        guard b.activity.isBusy else {
            if pillUp {
                send(["jsonrpc": "2.0", "id": nextID(), "method": "atoll.dismissLiveActivity",
                      "params": ["activityID": pillID, "bundleIdentifier": bundleID]])
                pillUp = false
                log("dismiss pill")
            }
            return
        }
        let d = pillDescriptor(b, id: pillID, bundleID: bundleID)
        let title = (d["title"] as? String ?? "") + (d["subtitle"] as? String ?? "")
        send(["jsonrpc": "2.0", "id": nextID(),
              "method": pillUp ? "atoll.updateLiveActivity" : "atoll.presentLiveActivity",
              "params": ["descriptor": d]])
        if !pillUp { log("present pill · \(b.activity.label)") }
        else if title != lastPillTitle { log("update pill · \(b.activity.label)") }
        pillUp = true
        lastPillTitle = title
    }
}

// 先探一次再连：不然第一帧会是 OFFLINE，一秒后才变 IDLE，刘海闪一下红。
being.tick()

// 本机服务：页面的数据来源与发信通道。token 只在这里补，不进 payload。
var localServer: LocalServer?
if config.enableChat {
    localServer = LocalServer(port: config.localPort, credentialsProvider: credentialsProvider, being: being)
    do {
        try localServer?.start()
        log("本机服务 http://127.0.0.1:\(config.localPort) 已起")
    } catch {
        log("本机服务起不来（\(error)）——刘海里的输入框会没数据")
    }
}

let bridge = Bridge(setupKey: localServer?.setupKey)
bridge.start()

// 轮询在自己的线程上跑，推帧只读结果——网络卡住不该让刘海跟着冻。
// 药丸上的计时也靠这一轮重画，所以这里就是唯一的节拍源：一秒一次。
// （原来主线程另有一个每秒的 tick，忙的时候等于每秒推两帧。）
let pollThread = Thread {
    while true {
        being.tick()
        bridge.tick()
        Thread.sleep(forTimeInterval: config.pollSeconds)
    }
}
pollThread.stackSize = 512 * 1024
pollThread.start()

while true { Thread.sleep(forTimeInterval: 3600) }
