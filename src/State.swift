// 状态判定。逐条照 being/touchbar/DESIGN.md 第三节的判据表，
// 加上 journal 09-05 那次实测更正（事件类型不止文档写的四种）。

import Foundation

enum Activity: String {
    case setup, offline, idle, thinking, working, replying

    /// 卡面上那半边会变的字，大写。journal 09-05「状态用强调色 semibold 大写」。
    var label: String { rawValue.uppercased() }

    /// 与 Loom TUI 同一层级的、给人看的状态词；闭合刘海只显示它，不显示
    /// reasoning 原文，既不泄露 scratchpad，也不会因逐 token 更新而闪烁。
    var loomLabel: String {
        switch self {
        case .setup: return "需要连接"
        case .offline: return "已离线"
        case .idle: return "已就绪"
        case .thinking: return "在思考"
        case .working: return "在行动"
        case .replying: return "在回复"
        }
    }

    var isBusy: Bool { self == .thinking || self == .working || self == .replying }

    /// loom.html 第 1673 行 effectiveDotClass()：离线走 error(红)，
    /// 活跃走 thinking(紫)，其余 connected(绿)。颜色只表示连接状态，不表示 SBS。
    var dotColor: RGB {
        switch self {
        case .setup: return .gray
        case .offline: return .red
        case .thinking, .working, .replying: return .purple
        case .idle: return .green
        }
    }
}

struct RGB {
    var r: Double, g: Double, b: Double, a: Double = 1
    // loom.html :root 的色板，原样搬过来，不另调。
    static let green = RGB(r: 0.247, g: 0.725, b: 0.314)   // #3fb950
    static let purple = RGB(r: 0.737, g: 0.549, b: 1.0)    // #bc8cff
    static let red = RGB(r: 0.973, g: 0.318, b: 0.286)     // #f85149
    static let gray = RGB(r: 0.490, g: 0.522, b: 0.565)    // #7d8590
    func alpha(_ a: Double) -> RGB { RGB(r: r, g: g, b: b, a: a) }
    var json: [String: Any] { ["red": r, "green": g, "blue": b, "alpha": a] }
}

struct BeingState: Equatable {
    /// 未连接前不假定用户的 Being 名称；连接成功后由 /api/status 的 being_name 覆盖。
    static let setupName = "连接 Being"

    var name = BeingState.setupName
    var activity: Activity = .offline
    var model = ""
    var sbsEnabled = true
    var thinkingDepth = ""
    /// 只保存 Loom 已对用户暴露的语义动作（例如「在搜索」），不是 reasoning 内容。
    /// 它变化时也要推 pill，才能让未 hover 的刘海与 Loom 同步。
    var activityDetail = ""
    /// 触发这条流的人类消息。DESIGN.md：「trigger_message 就是人类刚说的那句话」。
    var trigger = ""
    var streamStartedAt: Date? = nil

    static func == (a: BeingState, b: BeingState) -> Bool {
        a.name == b.name && a.activity == b.activity && a.model == b.model
            && a.sbsEnabled == b.sbsEnabled && a.trigger == b.trigger
            && a.activityDetail == b.activityDetail
    }

    /// SBS 关＝点停动画压暗到 0.4（loom.html 第 241 行）。
    /// 但 thinking 豁免：SBS 关的意思是「不自己起念」，不是「闲着」，
    /// 正在回你的时候必须看起来在干活（loom.html 第 1696 行的注释）。
    var dotIsDim: Bool { !sbsEnabled && activity != .thinking }

    var dotColor: RGB {
        let c = activity.dotColor
        return dotIsDim ? c.alpha(0.4) : c
    }

    /// 点的 class，照 loom.html 第 1673 行 effectiveDotClass() + 第 1698 行的 SBS 层。
    var dotClass: String {
        let base: String
        switch activity {
        case .setup: base = "setup"
        case .offline: base = "error"
        case .thinking, .working, .replying: base = "thinking"
        case .idle: base = "connected"
        }
        return dotIsDim ? "\(base) sbs-off" : base
    }

    /// 同一个颜色给 HTML 用。CSS 里不带透明度，暗淡交给 opacity，跟 loom 的做法一致。
    var dotHex: String {
        let c = activity.dotColor
        return String(format: "#%02x%02x%02x", Int(c.r * 255), Int(c.g * 255), Int(c.b * 255))
    }

    var liveLabel: String { activityDetail.isEmpty ? activity.loomLabel : activityDetail }

    /// 在跑时显示在回应哪句话，闲着显示模型，离线两样都不显示
    /// ——离线时不拿旧配置冒充当前状态（journal 09-05）。
    var secondLine: String? {
        switch activity {
        case .setup: return nil
        case .offline: return nil
        case .idle: return model.isEmpty ? nil : model
        default: return trigger.isEmpty ? (model.isEmpty ? nil : model) : trigger
        }
    }
}
