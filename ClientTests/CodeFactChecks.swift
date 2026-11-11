import Foundation
@testable import BerthClient

/// 运行中的服务是否在跑磁盘上现在的代码：引擎给判定，客户端只负责按 run id
/// 贴上，未知不冒充「没变」。
extension ClientChecks {
    static func codeFactChecks() throws {
        func group() throws -> BerthGroup {
            let json = #"{"name":"demo","repo":"demo","worktree":"","branch":"main","source":"file","services":[{"name":"api","cmd":"run","cwd":"/tmp","running":true}]}"#
            return try JSONDecoder().decode(BerthGroup.self, from: Data(json.utf8))
        }
        func run(_ id: String) throws -> RunRecord {
            let json = #"{"id":"\#(id)","pid":42,"group":"demo","name":"api","cmd":"run","cwd":"/tmp","started_at":"now","ports":[],"status":"running"}"#
            return try JSONDecoder().decode(RunRecord.self, from: Data(json.utf8))
        }
        let demo = try group()
        let current = try run("run-2")
        let stale = ServiceCodeFacts(name: "api", runID: "run-2", codeHead: "abc1234",
                                     changed: true, changedFiles: 2, hint: "oberth restart --only api")
        let ref = ServiceRef(group: "demo", service: "api")
        let store = ServicesStore(fixture: [demo], runs: RunsSnapshot(runs: [current], exited: []),
                                  codeFacts: [ref: stale])
        require(store.codeFact(demo.services[0], in: demo)?.isStale == true,
                "code fact for the live run was dropped")
        require(store.needsAttention(demo.services[0], in: demo),
                "running old code did not enter attention")

        // The same verdict must not stick to a newer run of the same service.
        let newer = try run("run-3")
        let moved = ServicesStore(fixture: [demo], runs: RunsSnapshot(runs: [newer], exited: []),
                                  codeFacts: [ref: stale])
        require(moved.codeFact(demo.services[0], in: demo) == nil,
                "a code verdict from an older run was attached to a newer process")
        require(!moved.needsAttention(demo.services[0], in: demo),
                "a stale-run verdict still demanded attention")

        // Unknown stays unknown: no fact means no chip and no attention.
        let none = ServicesStore(fixture: [demo], runs: RunsSnapshot(runs: [current], exited: []))
        require(none.codeFact(demo.services[0], in: demo) == nil,
                "a missing code fact was invented")
    }
}
