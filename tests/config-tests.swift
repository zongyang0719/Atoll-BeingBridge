import Foundation

@main
struct ConfigTests {
    static func main() {
        do {
            let credentials = try Config.credentials(
                fromBeingURL: "https://being.example:9443/loom/?token=abc%2F123"
            )
            try expect(credentials.base == "https://being.example:9443/loom", "base URL was not normalized")
            try expect(credentials.token == "abc/123", "token was not decoded")

            guard let endpoint = credentials.endpoint("/api/status"),
                  let query = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)?.queryItems,
                  query.first(where: { $0.name == "token" })?.value == "abc/123" else {
                throw TestFailure("endpoint did not preserve the token")
            }

            do {
                _ = try Config.credentials(fromBeingURL: "https://being.example/")
                throw TestFailure("missing token was accepted")
            } catch ConfigurationError.invalidBeingURL {
                // Expected.
            }

            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("being-notch-config-test-\(UUID().uuidString)", isDirectory: true)
            let secret = root.appendingPathComponent("being-url")
            defer { try? FileManager.default.removeItem(at: root) }
            try Config.saveBeingURL(
                "https://being.example/?token=test-token",
                at: secret.path
            )
            try expect(
                Config.storedBeingURL(at: secret.path) == "https://being.example/?token=test-token",
                "secure URL store did not round-trip"
            )
            let attributes = try FileManager.default.attributesOfItem(atPath: secret.path)
            let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o777
            try expect((mode & 0o077) == 0, "secret file is readable by group or others")

            let page = chatHTML(port: 9021, setupKey: "test-setup-key")
            try expect(page.utf8.count < 20_000, "embedded chat page exceeds Atoll's size limit")
            try expect(page.contains("/settings/test") && page.contains("/settings"),
                       "chat page does not expose the in-tab setup flow")
            try expect(page.contains("X-Being-Notch-Setup") && !page.contains("{{SETUP_KEY}}"),
                       "chat page does not protect its setup route")
            try expect(!page.contains("<h1>"),
                       "setup page repeats the native tab title and wastes its small viewport")
            try expect(!page.contains(".focus()"),
                       "chat page automatically focuses a control and keeps Atoll expanded")
            try expect(page.contains("window.addEventListener('mouseleave',releaseWebFocus)"),
                       "chat page does not release web focus after the pointer leaves")
            try expect(page.contains("function releaseWebFocus(){persistDraft();blurActiveElement()}"),
                       "leaving the panel can discard an unsent draft before Atoll closes")

            let neutralTab = notchDescriptor(
                BeingState(name: "Soul", activity: .idle),
                chatPort: 9021,
                chatHeight: 278,
                setupKey: "test-setup-key",
                id: "test.notch",
                bundleID: "io.github.beingnotch.test"
            )
            let neutralAccent = neutralTab["accentColor"] as? [String: Double]
            try expect(neutralAccent?["red"] == 1 && neutralAccent?["green"] == 1
                && neutralAccent?["blue"] == 1,
                       "notch tab overrides Atoll's neutral selected-icon color")

            print("config tests passed")
        } catch {
            fputs("config test failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw TestFailure(message) }
    }
}

private struct TestFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
