import Foundation
import SQLite3
import Testing
@testable import CapacityDock

@Suite("Capacity Dock active tasks")
struct CapacityDockActiveTaskTests {
    @Test("idle Cursor tracking does not invent a row")
    func idleCursorHasNoTasks() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try Self.writeTrackingDatabase(at: Self.cursorDB(home), rows: [])

        let tasks = CapacityDockLiveActivity.tasks(
            providerID: "cursor",
            since: Date(timeIntervalSince1970: 1_700_000_000),
            home: home
        )
        #expect(tasks.isEmpty)
    }

    @Test("recent Cursor edits become a live row titled from the file")
    func recentCursorEditMapsToTask() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 1_700_000_090)
        try Self.writeTrackingDatabase(
            at: Self.cursorDB(home),
            rows: [
                (
                    conversation: "conv-1",
                    file: "/Users/lu/project/parse_batch12_from_inspect.py",
                    timestamp: Int64(now.timeIntervalSince1970 * 1000) - 1_000
                )
            ]
        )
        try Self.writeComposerData(
            at: Self.cursorStateDB(home),
            id: "conv-1",
            name: nil,
            generating: true
        )

        let tasks = CapacityDockLiveActivity.tasks(
            providerID: "cursor",
            since: now.addingTimeInterval(-90),
            home: home
        )
        #expect(tasks == [
            CapacityDockActiveTask(id: "conv-1", title: "parse_batch12_from_inspect.py")
        ])
    }

    @Test("Cursor conversation name wins over the last hashed file")
    func cursorConversationTitleWinsOverFile() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 1_700_000_090)
        try Self.writeTrackingDatabase(
            at: Self.cursorDB(home),
            rows: [
                (
                    conversation: "884772cc-96ba-4147-81e2-ba80aa261d71",
                    file: "/Users/lu/Documents/Grok/capacity-dock/CONTRIBUTING.md",
                    timestamp: Int64(now.timeIntervalSince1970 * 1000) - 1_000
                )
            ]
        )
        try Self.writeConversationSearch(
            at: Self.cursorSearchDB(home),
            rows: [
                (
                    id: "884772cc-96ba-4147-81e2-ba80aa261d71",
                    title: "Capacity Dock integration setup",
                    updatedAt: nil
                )
            ]
        )
        try Self.writeComposerData(
            at: Self.cursorStateDB(home),
            id: "884772cc-96ba-4147-81e2-ba80aa261d71",
            name: nil,
            generating: true
        )

        let tasks = CapacityDockLiveActivity.tasks(
            providerID: "cursor",
            since: now.addingTimeInterval(-90),
            home: home
        )
        #expect(tasks == [
            CapacityDockActiveTask(
                id: "884772cc-96ba-4147-81e2-ba80aa261d71",
                title: "Capacity Dock integration setup"
            )
        ])
    }

    @Test("Cursor tracking summary title wins over conversation search")
    func cursorSummaryTitleWinsOverSearch() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 1_700_000_090)
        try Self.writeTrackingDatabase(
            at: Self.cursorDB(home),
            rows: [
                (
                    conversation: "conv-2",
                    file: "/tmp/CONTRIBUTING.md",
                    timestamp: Int64(now.timeIntervalSince1970 * 1000)
                )
            ],
            summaries: [
                (id: "conv-2", title: "From tracking summary")
            ]
        )
        try Self.writeConversationSearch(
            at: Self.cursorSearchDB(home),
            rows: [(id: "conv-2", title: "From conversation search", updatedAt: nil)]
        )
        try Self.writeComposerData(
            at: Self.cursorStateDB(home),
            id: "conv-2",
            name: nil,
            generating: true
        )

        let tasks = CapacityDockLiveActivity.tasks(
            providerID: "cursor",
            since: now.addingTimeInterval(-90),
            home: home
        )
        #expect(tasks == [
            CapacityDockActiveTask(id: "conv-2", title: "From tracking summary")
        ])
    }

    @Test("a live Cursor conversation shows without a file hash")
    func liveCursorConversationShowsWithoutHash() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 1_700_000_090)
        try Self.writeTrackingDatabase(at: Self.cursorDB(home), rows: [])
        try Self.writeConversationSearch(
            at: Self.cursorSearchDB(home),
            rows: [
                (
                    id: "884772cc-96ba-4147-81e2-ba80aa261d71",
                    title: "Capacity Dock integration setup",
                    updatedAt: Int64(now.timeIntervalSince1970 * 1000) - 5_000
                )
            ]
        )
        try Self.writeComposerData(
            at: Self.cursorStateDB(home),
            id: "884772cc-96ba-4147-81e2-ba80aa261d71",
            name: "Capacity Dock integration setup",
            generating: true
        )

        let tasks = CapacityDockLiveActivity.tasks(
            providerID: "cursor",
            since: now.addingTimeInterval(-90),
            home: home
        )
        #expect(tasks == [
            CapacityDockActiveTask(
                id: "884772cc-96ba-4147-81e2-ba80aa261d71",
                title: "Capacity Dock integration setup"
            )
        ])
    }

    @Test("an unfinished Cursor parent shows while thinking")
    func unfinishedCursorParentShowsWhileThinking() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 1_700_000_090)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        try Self.writeTrackingDatabase(at: Self.cursorDB(home), rows: [])
        try Self.writeComposerHeaders(
            at: Self.cursorStateDB(home),
            rows: [
                """
                {"type":"head","composerId":"89a50863-94d2-43e1-88cf-9d4c1ab93d6e","name":"第五批前逐行闭合","unfinishedRunAt":1700000000000,"conversationCheckpointLastUpdatedAt":\(nowMs),"unifiedMode":"agent","workspaceIdentifier":{"uri":{"fsPath":"/Users/lu/Desktop/纵横/项目/独立开发/vue_procurement_management_system"}}}
                """
            ]
        )
        try Self.writeComposerData(
            at: Self.cursorStateDB(home),
            id: "89a50863-94d2-43e1-88cf-9d4c1ab93d6e",
            name: "第五批前逐行闭合",
            generating: false
        )

        let tasks = CapacityDockLiveActivity.tasks(
            providerID: "cursor",
            since: now.addingTimeInterval(-90),
            home: home
        )
        #expect(tasks == [
            CapacityDockActiveTask(
                id: "89a50863-94d2-43e1-88cf-9d4c1ab93d6e",
                title: "第五批前逐行闭合",
                workspace: "vue_procurement_management_system"
            )
        ])
    }

    @Test("a parent leftover unfinishedRunAt with a stale checkpoint does not spin")
    func unfinishedCursorParentWithStaleCheckpointIsHidden() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 1_700_000_090)
        try Self.writeTrackingDatabase(at: Self.cursorDB(home), rows: [])
        try Self.writeComposerHeaders(
            at: Self.cursorStateDB(home),
            rows: [
                """
                {"type":"head","composerId":"89a50863-94d2-43e1-88cf-9d4c1ab93d6e","name":"第五批前逐行闭合","unfinishedRunAt":1700000000000,"conversationCheckpointLastUpdatedAt":1699999970000}
                """
            ]
        )
        try Self.writeComposerData(
            at: Self.cursorStateDB(home),
            id: "89a50863-94d2-43e1-88cf-9d4c1ab93d6e",
            name: "第五批前逐行闭合",
            generating: false
        )

        let tasks = CapacityDockLiveActivity.tasks(
            providerID: "cursor",
            since: now.addingTimeInterval(-90),
            home: home
        )
        #expect(tasks.isEmpty)
    }

    @Test("a finished Cursor conversation does not keep spinning")
    func finishedCursorConversationDoesNotSpin() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 1_700_000_090)
        try Self.writeTrackingDatabase(at: Self.cursorDB(home), rows: [])
        try Self.writeConversationSearch(
            at: Self.cursorSearchDB(home),
            rows: [
                (
                    id: "884772cc-96ba-4147-81e2-ba80aa261d71",
                    title: "Capacity Dock integration setup",
                    updatedAt: Int64(now.timeIntervalSince1970 * 1000) - 1_000
                )
            ]
        )
        try Self.writeComposerHeaders(
            at: Self.cursorStateDB(home),
            rows: [
                """
                {"type":"head","composerId":"884772cc-96ba-4147-81e2-ba80aa261d71","name":"Capacity Dock integration setup","unfinishedRunAt":1700000090000}
                """
            ]
        )
        try Self.writeComposerData(
            at: Self.cursorStateDB(home),
            id: "884772cc-96ba-4147-81e2-ba80aa261d71",
            name: "Capacity Dock integration setup",
            generating: false
        )

        let tasks = CapacityDockLiveActivity.tasks(
            providerID: "cursor",
            since: now.addingTimeInterval(-90),
            home: home
        )
        #expect(tasks.isEmpty)
    }

    @Test("an unfinished Cursor subagent stays live after the parent chat goes stale")
    func unfinishedCursorSubagentShowsWithoutParentUpdate() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 1_700_000_090)
        try Self.writeTrackingDatabase(at: Self.cursorDB(home), rows: [])
        try Self.writeConversationSearch(
            at: Self.cursorSearchDB(home),
            rows: [
                (
                    id: "89a50863-94d2-43e1-88cf-9d4c1ab93d6e",
                    title: "August fourth batch purchase orders",
                    updatedAt: Int64(now.timeIntervalSince1970 * 1000) - 600_000
                )
            ]
        )
        try Self.writeComposerHeaders(
            at: Self.cursorStateDB(home),
            rows: [
                """
                {"type":"head","composerId":"61a92507-f2fb-4298-913d-43aa5e0af62a","name":"8月第四批PO actual","unfinishedRunAt":1700000090000,"subagentInfo":{"parentComposerId":"89a50863-94d2-43e1-88cf-9d4c1ab93d6e","rootParentConversationId":"89a50863-94d2-43e1-88cf-9d4c1ab93d6e","subagentTypeName":"generalPurpose"}}
                """
            ]
        )
        try Self.writeComposerData(
            at: Self.cursorStateDB(home),
            id: "61a92507-f2fb-4298-913d-43aa5e0af62a",
            name: "8月第四批PO actual",
            generating: true,
            parentID: "89a50863-94d2-43e1-88cf-9d4c1ab93d6e"
        )

        let tasks = CapacityDockLiveActivity.tasks(
            providerID: "cursor",
            since: now.addingTimeInterval(-90),
            home: home
        )
        #expect(tasks == [
            CapacityDockActiveTask(
                id: "89a50863-94d2-43e1-88cf-9d4c1ab93d6e",
                title: "8月第四批PO actual"
            )
        ])
    }

    @Test("an unfinished Cursor subagent shows even between tool calls")
    func unfinishedCursorSubagentShowsWithoutLoadingHeader() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 1_700_000_090)
        try Self.writeTrackingDatabase(at: Self.cursorDB(home), rows: [])
        try Self.writeComposerHeaders(
            at: Self.cursorStateDB(home),
            rows: [
                """
                {"type":"head","composerId":"fa8406d8-503a-4891-b54a-f68def5b56d6","name":"AUG03第三批入库actual","unfinishedRunAt":1700000090000,"subagentInfo":{"parentComposerId":"89a50863-94d2-43e1-88cf-9d4c1ab93d6e","rootParentConversationId":"89a50863-94d2-43e1-88cf-9d4c1ab93d6e"}}
                """
            ]
        )
        try Self.writeComposerData(
            at: Self.cursorStateDB(home),
            id: "fa8406d8-503a-4891-b54a-f68def5b56d6",
            name: "AUG03第三批入库actual",
            generating: false,
            parentID: "89a50863-94d2-43e1-88cf-9d4c1ab93d6e"
        )

        let tasks = CapacityDockLiveActivity.tasks(
            providerID: "cursor",
            since: now.addingTimeInterval(-90),
            home: home
        )
        #expect(tasks == [
            CapacityDockActiveTask(
                id: "89a50863-94d2-43e1-88cf-9d4c1ab93d6e",
                title: "AUG03第三批入库actual"
            )
        ])
    }

    @Test("a finished Cursor composer header does not invent a row")
    func finishedCursorComposerIsHidden() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 1_700_000_090)
        try Self.writeTrackingDatabase(at: Self.cursorDB(home), rows: [])
        try Self.writeComposerHeaders(
            at: Self.cursorStateDB(home),
            rows: [
                """
                {"type":"head","composerId":"done-1","name":"Already finished","lastUpdatedAt":1700000000000}
                """
            ]
        )

        let tasks = CapacityDockLiveActivity.tasks(
            providerID: "cursor",
            since: now.addingTimeInterval(-90),
            home: home
        )
        #expect(tasks.isEmpty)
    }

    @Test("a stale Cursor conversation does not invent a row")
    func staleCursorConversationIsHidden() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 1_700_000_090)
        try Self.writeTrackingDatabase(at: Self.cursorDB(home), rows: [])
        try Self.writeConversationSearch(
            at: Self.cursorSearchDB(home),
            rows: [
                (
                    id: "stale-chat",
                    title: "Old thread",
                    updatedAt: Int64(now.timeIntervalSince1970 * 1000) - 120_000
                )
            ]
        )

        let tasks = CapacityDockLiveActivity.tasks(
            providerID: "cursor",
            since: now.addingTimeInterval(-90),
            home: home
        )
        #expect(tasks.isEmpty)
    }

    @Test("stale Cursor edits drop off after the live window")
    func staleCursorEditIsHidden() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 1_700_000_090)
        try Self.writeTrackingDatabase(
            at: Self.cursorDB(home),
            rows: [
                (
                    conversation: "conv-old",
                    file: "/tmp/done.swift",
                    timestamp: Int64(now.timeIntervalSince1970 * 1000) - 120_000
                )
            ]
        )

        let tasks = CapacityDockLiveActivity.tasks(
            providerID: "cursor",
            since: now.addingTimeInterval(-90),
            home: home
        )
        #expect(tasks.isEmpty)
    }

    @Test("Grok uses the generated session title")
    func grokUsesGeneratedTitle() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 1_700_000_090)
        let session = home
            .appendingPathComponent(".grok/sessions/%2FUsers%2Flu%2Fproject/01abc", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try Data("{\"generated_title\":\"Fix dock animation\"}".utf8).write(
            to: session.appendingPathComponent("summary.json")
        )
        try Data("x".utf8).write(to: session.appendingPathComponent("updates.jsonl"))
        try FileManager.default.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: session.appendingPathComponent("updates.jsonl").path
        )

        let tasks = CapacityDockLiveActivity.tasks(
            providerID: "grok",
            since: now.addingTimeInterval(-90),
            home: home
        )
        #expect(tasks == [
            CapacityDockActiveTask(id: "01abc", title: "Fix dock animation", workspace: "project")
        ])
    }

    @Test("Codex titles live rollouts from cwd")
    func codexUsesSessionCwd() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 1_700_000_090)
        let day = home.appendingPathComponent(".codex/sessions/2026/09/04", isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let file = day.appendingPathComponent("rollout-live.jsonl")
        let line = #"{"type":"session_meta","payload":{"cwd":"/Users/lu/Desktop/纵横数据"}}"# + "\n"
        try Data(line.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)

        let tasks = CapacityDockLiveActivity.tasks(
            providerID: "codex",
            since: now.addingTimeInterval(-90),
            home: home
        )
        #expect(tasks == [
            CapacityDockActiveTask(id: "rollout-live.jsonl", title: "纵横数据")
        ])
    }

    @Test("Codex joins workspace and sidebar thread name")
    func codexJoinsWorkspaceAndThreadName() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 1_700_000_090)
        let day = home.appendingPathComponent(".codex/sessions/2026/08/21", isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let id = "01a0242e-e9e1-7840-ad94-53d5219975aa"
        let file = day.appendingPathComponent(
            "rollout-2026-08-21T19-57-29-\(id).jsonl"
        )
        let line = #"{"type":"session_meta","payload":{"cwd":"/Users/lu/Desktop/纵横/纵横数据"}}"# + "\n"
        try Data(line.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
        try Self.writeCodexThreads(
            at: home.appendingPathComponent(".codex/state_5.sqlite"),
            rows: [
                (id: id, name: "ChatGPT Work｜采购订单扫描", path: file.path),
                (id: "other", name: "ignored", path: "/tmp/other.jsonl")
            ]
        )

        let tasks = CapacityDockLiveActivity.tasks(
            providerID: "codex",
            since: now.addingTimeInterval(-90),
            home: home
        )
        #expect(tasks == [
            CapacityDockActiveTask(
                id: file.lastPathComponent,
                title: "ChatGPT Work｜采购订单扫描",
                workspace: "纵横数据"
            )
        ])
    }

    @Test("Claude titles live transcripts from the project folder")
    func claudeUsesProjectFolder() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 1_700_000_090)
        let project = home.appendingPathComponent(".claude/projects/-Users-lu-work", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let file = project.appendingPathComponent("abc.jsonl")
        try Data("{}\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)

        let tasks = CapacityDockLiveActivity.tasks(
            providerID: "claude",
            since: now.addingTimeInterval(-90),
            home: home
        )
        #expect(tasks == [
            CapacityDockActiveTask(id: "abc.jsonl", title: "work")
        ])
    }

    @Test("Claude does not enter subagents transcripts")
    func claudeSkipsSubagents() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 1_700_000_090)
        let project = home.appendingPathComponent(".claude/projects/-Users-lu-work", isDirectory: true)
        let nested = project.appendingPathComponent("subagents", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let file = nested.appendingPathComponent("nested.jsonl")
        try Data("{}\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)

        let tasks = CapacityDockLiveActivity.tasks(
            providerID: "claude",
            since: now.addingTimeInterval(-90),
            home: home
        )
        #expect(tasks.isEmpty)
    }

    @Test("Grok does not reuse Cursor tracking")
    func grokDoesNotUseCursorTracking() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 1_700_000_090)
        try Self.writeTrackingDatabase(
            at: Self.cursorDB(home),
            rows: [
                (
                    conversation: "conv-1",
                    file: "/tmp/leak.swift",
                    timestamp: Int64(now.timeIntervalSince1970 * 1000)
                )
            ]
        )

        let tasks = CapacityDockLiveActivity.tasks(
            providerID: "grok",
            since: now.addingTimeInterval(-90),
            home: home
        )
        #expect(tasks.isEmpty)
    }

    @Test("snapshot routes by provider id")
    func snapshotRoutesByProvider() {
        let cursor = CapacityDockActiveTask(id: "c", title: "cursor")
        let grok = CapacityDockActiveTask(id: "g", title: "grok")
        let deps = CapacityDockActiveTaskSnapshot.Deps(
            now: { Date(timeIntervalSince1970: 1) },
            loadTasks: { id, _ in
                id == "cursor" ? [cursor] : id == "grok" ? [grok] : []
            }
        )
        #expect(CapacityDockActiveTaskSnapshot.tasks(for: Self.cursor, deps: deps) == [cursor])
        #expect(CapacityDockActiveTaskSnapshot.tasks(for: Self.grok, deps: deps) == [grok])
        #expect(CapacityDockActiveTaskSnapshot.tasks(for: Self.codex, deps: deps).isEmpty)
    }

    @Test("live task rows grow the detail card")
    func liveTasksGrowDetailHeight() {
        let quota = QuotaSummary(
            providerFilter: .cursor,
            connection: .connected,
            primary: QuotaSummary.Window(label: "Monthly", percent: 0.24, resetsAt: nil),
            details: [
                QuotaSummary.Window(label: "Monthly", percent: 0.24, resetsAt: nil)
            ],
            planLabel: "Ultra",
            footerLines: ["Source: Cursor app"]
        )
        let idle = CapacityDockMetrics.detailHeight(quota: quota, activeTaskCount: 0, scale: 1)
        let live = CapacityDockMetrics.detailHeight(quota: quota, activeTaskCount: 2, scale: 1)
        let labeled = CapacityDockMetrics.detailHeight(
            quota: quota,
            activeTaskCount: 2,
            activeTaskWorkspaceCount: 2,
            scale: 1
        )
        #expect(live > idle)
        #expect(live == idle + 10 + 36)
        #expect(labeled == live + 24)
    }

    @Test("file titles keep the last path component")
    func displayTitleUsesBasename() {
        #expect(LiveActivityPath.fileTitle("/a/b/c.swift") == "c.swift")
        #expect(LiveActivityPath.fileTitle("  ") == "Agent")
        #expect(LiveActivityPath.fileTitle(nil) == "Agent")
        #expect(LiveActivityPath.workspaceTitle("/Users/lu/Desktop/纵横数据") == "纵横数据")
        #expect(
            LiveActivityPath.displayWorkspace(
                "/Users/lu/Desktop/纵横/项目/独立开发/vue_procurement_management_system"
            ) == "vue_procurement_management_system"
        )
        #expect(LiveActivityPath.displayWorkspace(NSHomeDirectory()) == nil)
        #expect(
            LiveActivityPath.composerWorkspace([
                "workspaceIdentifier": [
                    "uri": ["fsPath": "/Users/lu/Documents/Grok/capacity-dock"]
                ]
            ]) == "capacity-dock"
        )
        #expect(
            LiveActivityPath.hierarchicalTitle(
                workspace: "纵横数据",
                thread: "ChatGPT Work｜采购订单扫描"
            ) == "纵横数据-ChatGPT Work｜采购订单扫描"
        )
        #expect(LiveActivityPath.hierarchicalTitle(workspace: "纵横数据", thread: nil) == "纵横数据")
        #expect(LiveActivityPath.hierarchicalTitle(workspace: "纵横数据", thread: "纵横数据") == "纵横数据")
        #expect(
            CodexLiveSessionStore.sessionID(
                fromRollout: "rollout-2026-08-21T19-57-29-01a0242e-e9e1-7840-ad94-53d5219975aa.jsonl"
            ) == "01a0242e-e9e1-7840-ad94-53d5219975aa"
        )
        #expect(LiveActivityPath.isIgnoredProcessName("Electron Helper"))
        #expect(LiveActivityPath.isIgnoredProcessName("crashpad_handler"))
        #expect(!LiveActivityPath.isIgnoredProcessName("updates.jsonl"))
    }

    private static var cursor: CapacityDockProvider { CapacityDockProvider(rawValue: "cursor")! }
    private static var grok: CapacityDockProvider { CapacityDockProvider(rawValue: "grok")! }
    private static var codex: CapacityDockProvider { CapacityDockProvider(rawValue: "codex")! }

    private static func makeHome() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("capacity-dock-active-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func cursorDB(_ home: URL) throws -> URL {
        let dir = home.appendingPathComponent(".cursor/ai-tracking", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ai-code-tracking.db")
    }

    private static func cursorSearchDB(_ home: URL) throws -> URL {
        let dir = home.appendingPathComponent(
            "Library/Application Support/Cursor/User/globalStorage",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("conversation-search.db")
    }

    private static func cursorStateDB(_ home: URL) throws -> URL {
        let dir = home.appendingPathComponent(
            "Library/Application Support/Cursor/User/globalStorage",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.vscdb")
    }

    private static func writeComposerHeaders(at url: URL, rows: [String]) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            sqlite3_close(database)
            throw TrackingFixtureError.open
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(
            database,
            "CREATE TABLE IF NOT EXISTS composerHeaders (composerId TEXT, value TEXT);",
            nil,
            nil,
            nil
        ) == SQLITE_OK else { throw TrackingFixtureError.create }
        for value in rows {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "INSERT INTO composerHeaders(composerId, value) VALUES (?, ?);",
                -1,
                &statement,
                nil
            ) == SQLITE_OK else { throw TrackingFixtureError.prepare }
            defer { sqlite3_finalize(statement) }
            guard let object = try? JSONSerialization.jsonObject(
                with: Data(value.utf8)
            ) as? [String: Any],
                let id = object["composerId"] as? String
            else { throw TrackingFixtureError.insert }
            sqlite3_bind_text(statement, 1, id, -1, sqliteTransientForActiveTaskTests)
            sqlite3_bind_text(statement, 2, value, -1, sqliteTransientForActiveTaskTests)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw TrackingFixtureError.insert }
        }
    }

    private static func writeComposerData(
        at url: URL,
        id: String,
        name: String?,
        generating: Bool,
        parentID: String? = nil
    ) throws {
        var object: [String: Any] = [
            "composerId": id,
            "status": generating ? "generating" : "completed",
            "generatingBubbleIds": generating ? ["bubble-live"] : [],
            "fullConversationHeadersOnly": [
                [
                    "type": 2,
                    "grouping": [
                        "toolFormerStatus": generating ? "loading" : "completed",
                        "shellStatus": generating ? "running" : "success"
                    ]
                ]
            ]
        ]
        if let name {
            object["name"] = name
        }
        if let parentID {
            object["subagentInfo"] = [
                "parentComposerId": parentID,
                "rootParentConversationId": parentID
            ]
        }
        let payload = try JSONSerialization.data(withJSONObject: object)
        guard let value = String(data: payload, encoding: .utf8) else {
            throw TrackingFixtureError.insert
        }

        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            sqlite3_close(database)
            throw TrackingFixtureError.open
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(
            database,
            "CREATE TABLE IF NOT EXISTS cursorDiskKV (key TEXT PRIMARY KEY, value TEXT);",
            nil,
            nil,
            nil
        ) == SQLITE_OK else { throw TrackingFixtureError.create }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "INSERT OR REPLACE INTO cursorDiskKV(key, value) VALUES (?, ?);",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else { throw TrackingFixtureError.prepare }
        defer { sqlite3_finalize(statement) }
        let key = "composerData:\(id)"
        sqlite3_bind_text(statement, 1, key, -1, sqliteTransientForActiveTaskTests)
        sqlite3_bind_text(statement, 2, value, -1, sqliteTransientForActiveTaskTests)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw TrackingFixtureError.insert }
    }

    private static func writeConversationSearch(
        at url: URL,
        rows: [(id: String, title: String, updatedAt: Int64?)]
    ) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            sqlite3_close(database)
            throw TrackingFixtureError.open
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(
            database,
            "CREATE TABLE conversations (id TEXT, title TEXT, updated_at INTEGER);",
            nil,
            nil,
            nil
        ) == SQLITE_OK else { throw TrackingFixtureError.create }
        for row in rows {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "INSERT INTO conversations(id, title, updated_at) VALUES (?, ?, ?);",
                -1,
                &statement,
                nil
            ) == SQLITE_OK else { throw TrackingFixtureError.prepare }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, row.id, -1, sqliteTransientForActiveTaskTests)
            sqlite3_bind_text(statement, 2, row.title, -1, sqliteTransientForActiveTaskTests)
            if let updatedAt = row.updatedAt {
                sqlite3_bind_int64(statement, 3, updatedAt)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw TrackingFixtureError.insert }
        }
    }

    private static func writeCodexThreads(
        at url: URL,
        rows: [(id: String, name: String, path: String)]
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            sqlite3_close(database)
            throw TrackingFixtureError.open
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(
            database,
            "CREATE TABLE threads (id TEXT, rollout_path TEXT, name TEXT);",
            nil,
            nil,
            nil
        ) == SQLITE_OK else { throw TrackingFixtureError.create }
        for row in rows {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "INSERT INTO threads(id, rollout_path, name) VALUES (?, ?, ?);",
                -1,
                &statement,
                nil
            ) == SQLITE_OK else { throw TrackingFixtureError.prepare }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, row.id, -1, sqliteTransientForActiveTaskTests)
            sqlite3_bind_text(statement, 2, row.path, -1, sqliteTransientForActiveTaskTests)
            sqlite3_bind_text(statement, 3, row.name, -1, sqliteTransientForActiveTaskTests)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw TrackingFixtureError.insert }
        }
    }

    private static func writeTrackingDatabase(
        at url: URL,
        rows: [(conversation: String, file: String, timestamp: Int64)],
        summaries: [(id: String, title: String)] = []
    ) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            sqlite3_close(database)
            throw TrackingFixtureError.open
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(
            database,
            """
            CREATE TABLE ai_code_hashes (
                hash TEXT,
                source TEXT,
                fileExtension TEXT,
                fileName TEXT,
                requestId TEXT,
                conversationId TEXT,
                timestamp INTEGER,
                model TEXT,
                createdAt INTEGER
            );
            """,
            nil,
            nil,
            nil
        ) == SQLITE_OK else { throw TrackingFixtureError.create }

        for row in rows {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "INSERT INTO ai_code_hashes(conversationId, fileName, timestamp) VALUES (?, ?, ?);",
                -1,
                &statement,
                nil
            ) == SQLITE_OK else { throw TrackingFixtureError.prepare }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, row.conversation, -1, sqliteTransientForActiveTaskTests)
            sqlite3_bind_text(statement, 2, row.file, -1, sqliteTransientForActiveTaskTests)
            sqlite3_bind_int64(statement, 3, row.timestamp)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw TrackingFixtureError.insert }
        }

        guard sqlite3_exec(
            database,
            """
            CREATE TABLE conversation_summaries (
                conversationId TEXT PRIMARY KEY,
                title TEXT,
                updatedAt INTEGER NOT NULL
            );
            """,
            nil,
            nil,
            nil
        ) == SQLITE_OK else { throw TrackingFixtureError.create }
        for summary in summaries {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "INSERT INTO conversation_summaries(conversationId, title, updatedAt) VALUES (?, ?, 1);",
                -1,
                &statement,
                nil
            ) == SQLITE_OK else { throw TrackingFixtureError.prepare }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, summary.id, -1, sqliteTransientForActiveTaskTests)
            sqlite3_bind_text(statement, 2, summary.title, -1, sqliteTransientForActiveTaskTests)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw TrackingFixtureError.insert }
        }
    }

    private enum TrackingFixtureError: Error {
        case open
        case create
        case prepare
        case insert
    }
}

private let sqliteTransientForActiveTaskTests = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
