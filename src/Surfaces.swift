// 两个面的帧。字段形状照 AtollExtensionKit 的模型；
// 枚举写成 {"type":"…"}，宿主解码前会跑 transformClientJSON 改写成 {"symbol":{…}}。

import Foundation

// tab.preferredHeight 合法区间 [160, 420]。低于 160 整个 descriptor 判无效，
// 而且被拒不写 rateLimit 记录，看起来就像从没发过——老桥卡的就是这一格。
let tabHeightMin = 160.0
let tabHeightMax = 420.0

func fontJSON(_ size: Double, _ weight: String, mono: Bool = false) -> [String: Any] {
    ["design": "default", "size": size, "weight": weight, "isMonospacedDigit": mono]
}

func dotIcon(_ size: Double) -> [String: Any] {
    // 就是 loom 那个点。不换别的符号——颜色和明暗已经把状态说完了。
    ["type": "symbol", "name": "circle.fill", "size": size, "weight": "semibold"]
}

/// 聊天关闭时的只读后备页。只显示 Being 的身份与状态，不再混入第二种服务数据。
func statusHTML(_ b: BeingState) -> String {
    """
    <style>
      *{margin:0;padding:0;box-sizing:border-box}
      body{height:100%;display:flex;align-items:center;font-family:-apple-system,'SF Pro Text',system-ui;color:#e6edf3}
      .identity{display:flex;align-items:center;gap:9px;min-width:0}
      .dot{width:10px;height:10px;border-radius:50%;flex:none;background:\(b.dotHex);transition:background .3s}
      .dot.connected{animation:breathe 3s ease-in-out infinite}
      .dot.thinking,.dot.error,.dot.reconnecting{animation:pulse 1.2s ease-in-out infinite}
      .dot.sbs-off{animation:none;opacity:.4}
      .copy{display:flex;flex-direction:column;gap:3px;min-width:0}
      .name{font-size:14px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
      .status{font-size:11px;font-weight:650;letter-spacing:.08em;color:\(b.dotHex);\(b.dotIsDim ? "opacity:.55;" : "")}
      @keyframes breathe{0%,100%{opacity:.45;transform:scale(1)}50%{opacity:1;transform:scale(1.2)}}
      @keyframes pulse{0%,100%{opacity:.4;transform:scale(1)}50%{opacity:1;transform:scale(1.3)}}
      @media (prefers-reduced-motion:reduce){.dot{animation:none!important}}
    </style>
    <div class="identity">
      <span class="dot \(b.dotClass)"></span>
      <div class="copy"><span class="name">\(b.name)</span><span class="status">\(b.activity.label)</span></div>
    </div>
    """
}

/// 常驻标签。默认是可交互的 Soul 聊天页；关闭聊天时才显示上面的只读后备页。
func notchDescriptor(_ b: BeingState, chatPort: UInt16?, chatHeight: Double, setupKey: String?,
                     id: String, bundleID: String) -> [String: Any] {
    // 能打字的那版：HTML 是静态壳，值由页面自己去本机取。
    // 一个字都不插值，重推时 updateNSView 才不会 reload、才不会吃掉正在输入的字。
    if let chatPort {
        let web: [String: Any] = [
            "html": chatHTML(port: chatPort, setupKey: setupKey ?? ""),
            // tab.preferredHeight 是整个面板高度；网页区已留出标准聊天所需的内容空间。
            "preferredHeight": chatHeight,
            "isTransparent": true,
            "allowLocalhostRequests": true,
            "allowRemoteRequests": false,
            // 让聊天列保持 Loom 的阅读宽度，别随着刘海面板横向拉成一根输入条。
            "maximumContentWidth": 560,
        ]
        return [
            "id": id, "bundleIdentifier": bundleID, "priority": "normal",
            // 同一状态色用于标签、标题前的状态点，避免泛用的拼图图标和 Lottie 背板。
            "accentColor": b.dotColor.json, "metadata": [:], "durationHint": 21_600,
            "tab": ["title": b.name,
                    "iconSymbolName": "sparkles",
                    "badgeIcon": dotIcon(12),
                    // preferredHeight 是整个面板高度，不是内容区。
                    "preferredHeight": tabHeightMax,
                    "allowWebInteraction": true,
                    "sections": [], "webContent": web],
        ]
    }

    let webHeight = 44.0
    let web: [String: Any] = [
        "html": statusHTML(b),
        "preferredHeight": webHeight,
        "isTransparent": true,
        "allowLocalhostRequests": false,
        "allowRemoteRequests": false,
    ]
    let tab: [String: Any] = [
        "title": " ",
        "badgeIcon": ["type": "none"],
        "preferredHeight": max(tabHeightMin, webHeight + 84),
        "allowWebInteraction": false,
        "sections": [],
        "webContent": web,
    ]
    return [
        "id": id,
        "bundleIdentifier": bundleID,
        "priority": "normal",
        "accentColor": b.dotColor.json,
        "metadata": [:],
        "durationHint": 21_600,
        "tab": tab,
    ]
}

/// 跃迁药丸。只在真的在动时出现，安静就撤掉——
/// 常驻那半边已经在标签页里了，闲着还挂个药丸是重复。
func pillDescriptor(_ b: BeingState, id: String, bundleID: String) -> [String: Any] {
    var d: [String: Any] = [
        "id": id,
        "bundleIdentifier": bundleID,
        "priority": "normal",
        "accentColor": b.dotColor.json,
        "metadata": [:],
        "allowsMusicCoexistence": true,
        "centerTextStyle": "inheritUser",
        "leadingIcon": dotIcon(10),
        // 非 hover 的唯一信息就是与 Loom 同步的语义状态；不显示原始思维链。
        "title": "\(b.name) · \(b.liveLabel)",
        "sneakPeekConfig": ["enabled": true, "duration": 3, "showOnUpdate": false, "style": "standard"],
    ]
    if !b.trigger.isEmpty { d["subtitle"] = String(b.trigger.prefix(90)) }
    if let started = b.streamStartedAt {
        let s = Int(Date().timeIntervalSince(started))
        d["trailingContent"] = ["type": "text",
                                "text": s < 60 ? "\(s)s" : "\(s / 60)m\(s % 60)s",
                                "font": fontJSON(12, "medium", mono: true)]
    }
    return d
}
