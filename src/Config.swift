// 公开配置边界：
// - 非敏感显示与轮询参数放 config.json；
// - 带 token 的 Being URL 单独存为仅当前用户可读的 being-url；
// - URL 永不进入 Atoll payload、网页、日志或仓库。

import Foundation

enum ConfigurationError: LocalizedError {
    case invalidBeingURL

    var errorDescription: String? {
        switch self {
        case .invalidBeingURL:
            return "请输入带 ?token= 的完整 http(s) Being URL。"
        }
    }
}

struct BeingCredentials {
    let base: String
    let token: String

    /// 所有上游请求都由这一处补 token，避免调用点自己拼接或泄漏到网页。
    func endpoint(_ path: String) -> URL? {
        guard var components = URLComponents(string: base + path) else { return nil }
        var query = components.queryItems ?? []
        query.removeAll { $0.name.lowercased() == "token" }
        query.append(URLQueryItem(name: "token", value: token))
        components.queryItems = query
        return components.url
    }
}

struct Config {
    /// 刘海里能直接打字。开了之后页面变成静态壳、自己去本机取数据，
    /// daemon 不再靠重推来更新状态——重推会 reload webview，把你正在打的字冲掉。
    var enableChat = true
    var localPort: UInt16 = 9021
    /// 宿主允许扩展 tab 最高 420pt；给滚动中的回复和一行 composer 多留一点纵向空间。
    var chatWebHeight = 278.0
    var pollSeconds = 1.0
    var offlineAfterFailures = 3

    static let dir = NSString(string: "~/.being-notch").expandingTildeInPath
    static let path = dir + "/config.json"
    static let beingURLPath = dir + "/being-url"

    static func load() -> Config {
        var c = Config()
        guard let d = FileManager.default.contents(atPath: path),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            c.write()
            return c
        }
        if let v = o["enableChat"] as? Bool { c.enableChat = v }
        if let v = o["localPort"] as? Int, let p = UInt16(exactly: v) { c.localPort = p }
        if let v = o["chatWebHeight"] as? Double { c.chatWebHeight = v }
        if let v = o["pollSeconds"] as? Double { c.pollSeconds = v }
        if let v = o["offlineAfterFailures"] as? Int { c.offlineAfterFailures = v }
        return c
    }

    func write() {
        let o: [String: Any] = [
            "enableChat": enableChat,
            "localPort": Int(localPort),
            "chatWebHeight": chatWebHeight,
            "pollSeconds": pollSeconds,
            "offlineAfterFailures": offlineAfterFailures,
        ]
        guard let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? FileManager.default.createDirectory(atPath: Self.dir, withIntermediateDirectories: true)
        try? d.write(to: URL(fileURLWithPath: Self.path), options: .atomic)
    }

    /// 接收用户从 Loom 复制的一条 URL，例如 https://host:port/?token=...
    /// URL 中除了 token 的 query 参数不参与 bridge 的上游请求，避免把页面路由误当 API 根。
    static func credentials(fromBeingURL raw: String) throws -> BeingCredentials {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: input),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil,
              let token = components.queryItems?.first(where: { $0.name.lowercased() == "token" })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw ConfigurationError.invalidBeingURL
        }

        components.queryItems = nil
        components.fragment = nil
        guard var base = components.url?.absoluteString else {
            throw ConfigurationError.invalidBeingURL
        }
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty else { throw ConfigurationError.invalidBeingURL }
        return BeingCredentials(base: base, token: token)
    }

    static func hasStoredBeingURL(at path: String = beingURLPath) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// 只读取 URL，不把它显示、日志化或传给 WebView。
    static func storedBeingURL(at path: String = beingURLPath) -> String? {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func saveBeingURL(_ raw: String, at path: String = beingURLPath) throws {
        _ = try credentials(fromBeingURL: raw)
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        let url = URL(fileURLWithPath: path)
        try Data(value.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: path
        )
    }

    func beingCredentials() -> BeingCredentials? {
        guard let url = Self.storedBeingURL() else { return nil }
        return try? Self.credentials(fromBeingURL: url)
    }
}
