import SwiftUI

/// One declared service — hover/selection wash, progressive actions.
///
/// Stage craft v9 layout (operator-console data surface):
/// - **Name**: single primary line
/// - **Status**: calm chip (live / warn / quiet) — own optical column
/// - **Port**: tabular mono
/// - **Command**: single line (notice replaces cmd when present)
/// - **Actions**: progressive chips on hover/focus
struct ServiceRow: View {
    let service: BerthService
    let isLive: Bool
    let isFocused: Bool
    let isWorking: Bool
    let notice: String?
    /// 这次运行和磁盘上现在的源码比较。nil 表示未知 —— 不显示「已变/未变」。
    var code: ServiceCodeFacts? = nil
    /// 冻结渲染里不要挂原生 tooltip：`ImageRenderer` 会把它画进图里。
    var showsHelp: Bool = true
    let onFocus: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void

    @State private var hovering = false

    enum Col {
        static var spacing: CGFloat { Metrics.columnGap }
        static let dot: CGFloat = 14
        /// Name is primary only; status moved to its own column.
        static let name: CGFloat = 108
        /// Calm status chip column — lockstep with ServicesView.Col.status.
        static let status: CGFloat = 84
        static var port: CGFloat { Metrics.portColumn }
        static let action: CGFloat = 112
        static let actionChip: CGFloat = 40

        static let primaryLine: CGFloat = 17
        static let verticalPad: CGFloat = 10
    }

    static var height: CGFloat {
        Col.verticalPad + Col.primaryLine + Col.verticalPad
    }

    /// Ops-workbench: attention rows keep CLI verbs visible (start/restart/stop).
    private var showActions: Bool {
        hovering || isFocused || service.needsAttention || (code?.isStale ?? false)
    }

    private var commandText: String {
        if let notice, !notice.isEmpty { return notice }
        return service.cmd.isEmpty ? "—" : service.cmd
    }

    private var commandIsNotice: Bool { notice.map { !$0.isEmpty } ?? false }

    /// Status chip for the dedicated 状态 column.
    private var statusChip: (text: String, tone: Tag.Tone)? {
        if service.manifestRuntimeMismatch {
            return ("需重启", .warn)
        }
        if let health = service.healthStatus {
            switch health.status {
            case "ok":
                break
            case "fail":
                return ("健康失败", .warn)
            default:
                return ("健康未知", .warn)
            }
        }
        if let exit = service.lastExit {
            let label: String = {
                switch exit.reason {
                case "ready_timeout": return "就绪超时"
                case "crashed": return "已崩溃"
                case "start_failed": return "启动失败"
                case "port_occupied": return "端口占用"
                case "dependency_timeout": return "依赖超时"
                case "dependency_not_ready": return "依赖未就绪"
                default: return "已退出"
                }
            }()
            return (label, .warn)
        }
        if let code, code.isStale {
            return ("代码已变", .warn)
        }
        if let health = service.healthStatus, health.status == "ok" {
            return ("就绪", .live)
        }
        if service.health != nil && service.running {
            return ("检查中", .quiet)
        }
        if isLive {
            return ("在跑", .live)
        }
        return ("未启动", .quiet)
    }

    /// 状态标签背后的证据。代码过期这一条来自引擎的 `groups.code`，和 CLI
    /// `status` 的 `code_changed_since_start` 是同一组事实。
    private var statusHelp: String? {
        if service.manifestRuntimeMismatch {
            return "清单改过，进程还是按旧清单起的；重启后生效"
        }
        // 标签优先显示健康和退出；那些原因在详情里有，这里不再抢一句话。
        if let health = service.healthStatus, health.status != "ok" { return nil }
        if service.lastExit != nil { return nil }
        if let code, code.isStale {
            var parts = ["这个进程跑的是旧代码"]
            if let files = code.changedFiles, files > 0 {
                parts.append("\(files) 个文件已改")
            }
            if let head = code.codeHead, !head.isEmpty {
                parts.append("启动时 HEAD \(head.prefix(7))")
            }
            if let hint = code.hint, !hint.isEmpty {
                parts.append(hint)
            }
            return parts.joined(separator: " · ")
        }
        return nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: Col.spacing) {
            StatusDot(tone: isLive ? Ink.live : Ink.dormant)
                .frame(width: Col.dot, alignment: .leading)

            Text(service.name)
                .font(Face.sans(Metrics.row, .semibold))
                .foregroundStyle(isLive ? Ink.ink : Ink.inkMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: Col.name, alignment: .leading)

            Group {
                if let statusChip {
                    Tag(text: statusChip.text, tone: statusChip.tone)
                } else {
                    Text("—")
                        .font(Face.sans(Metrics.meta))
                        .foregroundStyle(Ink.inkFaint)
                }
            }
            .frame(width: Col.status, alignment: .leading)
            .modifier(HelpIfPresent(text: showsHelp ? statusHelp : nil))

            Text(verbatim: service.shownPort.map { "\($0)" } ?? "—")
                .font(Face.mono(Metrics.chrome, .medium))
                .monospacedDigit()
                .foregroundStyle(Ink.inkMuted)
                .lineLimit(1)
                .frame(width: Col.port, alignment: .trailing)

            Text(commandText)
                .font(commandIsNotice ? Face.sans(Metrics.chrome) : Face.mono(Metrics.meta))
                .foregroundStyle(commandIsNotice ? Ink.ink : Ink.inkFaint)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()

            actions
                .frame(width: Col.action, alignment: .trailing)
                .layoutPriority(1)
                .opacity(showActions || isWorking ? 1 : 0)
                .allowsHitTesting(showActions || isWorking)
                .animation(Motion.hover, value: showActions)
        }
        .padding(.horizontal, Metrics.gutter)
        .frame(height: Self.height, alignment: .center)
        .background(rowWash)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(perform: onFocus)
        .onHover { now in
            withAnimation(Motion.hover) { hovering = now }
        }
        .accessibilityAddTraits(isFocused ? .isSelected : [])
        .accessibilityAction(named: Text("选中服务"), onFocus)
    }

    @ViewBuilder private var actions: some View {
        if isWorking {
            Text("…")
                .font(Face.sans(Metrics.chrome))
                .foregroundStyle(Ink.inkFaint)
                .frame(minWidth: Col.actionChip, alignment: .trailing)
        } else if isLive {
            HStack(spacing: Metrics.unit) {
                RowAction(title: "重启", tone: Ink.accent, minWidth: Col.actionChip, action: onRestart)
                RowAction(title: "停止", minWidth: Col.actionChip, action: onStop)
            }
        } else {
            RowAction(title: "启动", tone: Ink.accent, minWidth: Col.actionChip, action: onStart)
        }
    }

    private var rowWash: some View {
        ZStack(alignment: .leading) {
            if isFocused {
                // v11: whisper blush wash + thin terracotta rail — never alarm flood.
                Ink.accentSoft.opacity(0.78)
            } else if hovering {
                Ink.surface.opacity(0.85)
            } else {
                Color.clear
            }
            if isFocused {
                Rectangle()
                    .fill(Ink.accent)
                    .frame(width: 2)
            }
        }
    }
}


/// 只在有内容时挂 help：空字符串会留下一个空 tooltip。
private struct HelpIfPresent: ViewModifier {
    let text: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let text, !text.isEmpty {
            content.help(text)
        } else {
            content
        }
    }
}
