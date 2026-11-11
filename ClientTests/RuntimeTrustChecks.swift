import Foundation
@testable import BerthClient

/// The three trust gaps this branch closes, checked at the model and policy
/// layer (the visual layer is covered by `--render-states`):
///
/// 1. "not observed" is not "not listening";
/// 2. a stop signal receipt is not an exit, and every target gets its own
///    answer;
/// 3. running old code is shown from the engine's verdict, not inferred.
extension ClientChecks {
    static func runtimeTrustChecks() throws {
        try machineRefChecks()
        try observationDecodeChecks()
        try codeFactChecks()
        stopNoticeChecks()
        print("PASS: unobserved vs not-listening, observation deltas, code-fact join and per-target stop results")
    }

    private static func machineRefChecks() throws {
        func ref(_ json: String) throws -> BerthMachineRef {
            try JSONDecoder().decode(BerthMachineRef.self, from: Data(json.utf8))
        }
        let unknown = try ref(#"{"name":"pg","port":5432,"listening":false}"#)
        require(unknown.listeningUnknown && !unknown.observedNotListening,
                "a missing listening_known was read as a proven negative")
        let narrow = try ref(#"{"name":"pg","port":5432,"listening":false,"listening_known":false}"#)
        require(narrow.listeningUnknown && !narrow.observedNotListening,
                "an uncovered table turned absence into 'not listening'")
        let known = try ref(#"{"name":"pg","port":5432,"listening":false,"listening_known":true}"#)
        require(known.observedNotListening && !known.listeningUnknown,
                "a covered table's negative was not kept as a fact")
        let seen = try ref(#"{"name":"pg","port":5432,"listening":true,"listening_known":false}"#)
        require(seen.listening && !seen.listeningUnknown,
                "a row that was actually in the table was discarded as unknown")
    }

    private static func observationDecodeChecks() throws {
        let partial = try JSONDecoder().decode(
            ListenerObservation.self,
            from: Data(#"{"state":"partial","code":"observation_incomplete","source":"lsof","detail":"2 rows","hint":"doctor"}"#.utf8))
        require(!partial.isTrusted && partial.isPartial && !partial.isBlind,
                "a narrow/partial verdict was treated as trusted")

        let blind = try JSONDecoder().decode(
            ListenerObservation.self,
            from: Data(#"{"state":"blind","code":"observation_blind"}"#.utf8))
        require(blind.isBlind && !blind.isTrusted && !blind.isPartial,
                "a blind verdict was not separated from a partial table")

        let base = #"{"seq":2,"at":"now","ports":{"added":[],"updated":[],"removed":[]},"groups":{"added":[],"updated":[],"removed":[]}}"#
        let absent = try JSONDecoder().decode(DaemonStateDelta.self, from: Data(base.utf8))
        require(!absent.observationPresent && absent.observation == nil,
                "an old daemon's delta claimed a new observation verdict")

        let cleared = try JSONDecoder().decode(
            DaemonStateDelta.self,
            from: Data((String(base.dropLast()) + #","observation":null}"#).utf8))
        require(cleared.observationPresent && cleared.observation == nil,
                "an explicit null did not clear the stale verdict")

        let moved = try JSONDecoder().decode(
            DaemonStateDelta.self,
            from: Data((String(base.dropLast()) + #","observation":{"state":"blind","code":"observation_blind"}}"#).utf8))
        require(moved.observationPresent && moved.observation?.isBlind == true,
                "an observation-only delta lost its verdict")

        let snapshot = try JSONDecoder().decode(
            DaemonStateSnapshot.self,
            from: Data(#"{"seq":1,"at":"now","ports":[],"groups":[],"observation":{"state":"partial","source":"lsof"}}"#.utf8))
        require(snapshot.observation?.isPartial == true,
                "the opening frame dropped the listener coverage verdict")
    }

    private static func stopNoticeChecks() {
        let wire = try! JSONDecoder().decode(
            KillRow.self,
            from: Data(#"{"ok":false,"error":"no process with PID 9","code":"not_found","pid":9,"name":""}"#.utf8))
        require(wire.alreadyGone && !wire.failed,
                "a not_found wire row was classified as a failure")
        let denied = try! JSONDecoder().decode(
            KillRow.self,
            from: Data(#"{"ok":false,"error":"permission denied","code":"permission_denied","pid":9,"name":"api"}"#.utf8))
        require(denied.failed && !denied.alreadyGone,
                "a permission failure was classified as already gone")
        let summary = KillReport(ok: false, rows: [denied]).summary
        require(summary?.contains("api") == true && summary?.contains("permission denied") == true,
                "the stop summary lost which target failed and why")

        func run(_ id: String, pid: Int = 42, name: String = "api") -> RunRecord {
            let json = #"{"id":"\#(id)","pid":\#(pid),"group":"demo","name":"\#(name)","cmd":"run","cwd":"/tmp","started_at":"now","ports":[],"status":"running"}"#
            return try! JSONDecoder().decode(RunRecord.self, from: Data(json.utf8))
        }
        func after(_ rows: [RunRecord]) -> RunsSnapshot { RunsSnapshot(runs: rows, exited: []) }

        let target = run("run-1")
        let failedRow = KillRow(ok: false, error: "permission denied", code: "permission_denied", pid: 42, name: "api")
        let failed = ServicesStore.stopNotices(
            outcomes: [(target, .success(KillReport(ok: false, rows: [failedRow])))],
            after: after([]))
        require(failed["run-1"]?.contains("permission denied") == true,
                "a failed row was reported as stopped")

        let stillThere = ServicesStore.stopNotices(
            outcomes: [(target, .success(KillReport(ok: true, rows: [KillRow(ok: true, pid: 42)])))],
            after: after([target]))
        require(stillThere["run-1"]?.contains("仍在注册表里") == true,
                "a run still in the registry was reported as stopped")

        let stopped = ServicesStore.stopNotices(
            outcomes: [(target, .success(KillReport(ok: true, rows: [KillRow(ok: true, pid: 42)])))],
            after: after([]))
        require(stopped["run-1"] == nil,
                "a verified exit produced a warning")

        let alreadyGone = ServicesStore.stopNotices(
            outcomes: [(target, .success(KillReport(ok: true, rows: [
                KillRow(ok: false, error: "no such process", code: "not_found", pid: 42)])))],
            after: after([]))
        require(alreadyGone["run-1"] == nil,
                "not_found was treated as a stop failure")

        let unverified = ServicesStore.stopNotices(
            outcomes: [(target, .success(KillReport(ok: true, rows: [KillRow(ok: true, pid: 42)])))],
            after: nil)
        require(unverified["run-1"]?.contains("没能复核") == true,
                "a signal receipt without exit evidence was treated as success")

        let thrown = ServicesStore.stopNotices(
            outcomes: [(target, .failure(DaemonClient.Failure.malformed("frame unreadable")))],
            after: after([]))
        require(thrown["run-1"]?.contains("frame unreadable") == true,
                "a transport failure was dropped")
    }
}
