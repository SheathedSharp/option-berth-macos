import Foundation

/// A listener reported by `state.snapshot`.
///
/// Ports are evidence attached to a worktree or run. The client keeps the
/// daemon's attribution fields and never invents a machine-wide category.
struct Port: Decodable, Identifiable, Sendable {
    let port: Int
    let bindAddress: String
    let pid: Int
    let process: String
    let displayName: String
    let url: String?
    let cwd: String?
    let cwdInTrash: Bool
    let cwdGone: Bool
    let projectRoot: String?
    let group: String?
    let command: String?

    var id: String { "\(port):\(bindAddress)" }

    var isOnLan: Bool {
        !bindAddress.hasPrefix("127.") && bindAddress != "::1" && bindAddress != "localhost"
    }

    var projectName: String? {
        if let group, !group.isEmpty { return group }
        guard let root = projectRoot, !root.isEmpty else { return nil }
        return URL(fileURLWithPath: root).lastPathComponent
    }

    private enum CodingKeys: String, CodingKey {
        case port, pid, process, url, cwd, group, command
        case bindAddress = "bind_address"
        case displayName = "display_name"
        case cwdInTrash = "cwd_in_trash"
        case cwdGone = "cwd_gone"
        case projectRoot = "project_root"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        port = (try? c.decode(Int.self, forKey: .port)) ?? 0
        pid = (try? c.decode(Int.self, forKey: .pid)) ?? 0
        bindAddress = Port.string(c, .bindAddress) ?? ""
        process = Port.string(c, .process) ?? ""
        displayName = Port.string(c, .displayName) ?? process
        url = Port.string(c, .url)
        cwd = Port.string(c, .cwd)
        cwdInTrash = (try? c.decode(Bool.self, forKey: .cwdInTrash)) ?? false
        cwdGone = (try? c.decode(Bool.self, forKey: .cwdGone)) ?? false
        projectRoot = Port.string(c, .projectRoot)
        group = Port.string(c, .group)
        command = Port.string(c, .command)
    }

    private static func string(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        try? c.decodeIfPresent(String.self, forKey: key)
    }
}

/// 这一轮监听表能不能被相信。引擎在 `state.snapshot` 和首帧订阅里发布它；
/// `blind` / `bind_denied` / `partial` / 非主采集器（`source` 非空）都意味着
/// **表里没有的端口是未知**，不是空着。
struct ListenerObservation: Decodable, Sendable, Equatable {
    let state: String
    let code: String
    /// 非主采集器（Darwin 上的 `lsof`）。非空即窄表：看不到别的用户的 socket。
    let source: String
    let detail: String
    let hint: String
    let checkedAt: String

    /// 完整、可信的一次观察。
    var isTrusted: Bool { state == "observable" && source.isEmpty }

    /// 表还在，但覆盖不完整（窄表或部分行读不出来）。
    var isPartial: Bool {
        if source.isEmpty == false { return true }
        return state == "partial"
    }

    /// 完全看不到监听表。
    var isBlind: Bool { state == "blind" || state == "bind_denied" }

    private enum CodingKeys: String, CodingKey {
        case state, code, source, detail, hint
        case checkedAt = "checked_at"
    }

    init(state: String, code: String = "", source: String = "", detail: String = "",
         hint: String = "", checkedAt: String = "") {
        self.state = state
        self.code = code
        self.source = source
        self.detail = detail
        self.hint = hint
        self.checkedAt = checkedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = (try? c.decode(String.self, forKey: .state)) ?? ""
        code = (try? c.decode(String.self, forKey: .code)) ?? ""
        source = (try? c.decode(String.self, forKey: .source)) ?? ""
        detail = (try? c.decode(String.self, forKey: .detail)) ?? ""
        hint = (try? c.decode(String.self, forKey: .hint)) ?? ""
        checkedAt = (try? c.decode(String.self, forKey: .checkedAt)) ?? ""
    }
}
