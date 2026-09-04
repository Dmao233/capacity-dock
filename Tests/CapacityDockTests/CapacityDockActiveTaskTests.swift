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

        let tasks = CapacityDockLiveActivity.tasks(
            providerID: "cursor",
            since: now.addingTimeInterval(-90),
            home: home
        )
        #expect(tasks == [
            CapacityDockActiveTask(id: "conv-1", title: "parse_batch12_from_inspect.py")
        ])
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
            CapacityDockActiveTask(id: "01abc", title: "Fix dock animation")
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
        #expect(live > idle)
        #expect(live == idle + 10 + 36)
    }

    @Test("file titles keep the last path component")
    func displayTitleUsesBasename() {
        #expect(LiveActivityPath.fileTitle("/a/b/c.swift") == "c.swift")
        #expect(LiveActivityPath.fileTitle("  ") == "Agent")
        #expect(LiveActivityPath.fileTitle(nil) == "Agent")
        #expect(LiveActivityPath.workspaceTitle("/Users/lu/Desktop/纵横数据") == "纵横数据")
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

    private static func writeTrackingDatabase(
        at url: URL,
        rows: [(conversation: String, file: String, timestamp: Int64)]
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
    }

    private enum TrackingFixtureError: Error {
        case open
        case create
        case prepare
        case insert
    }
}

private let sqliteTransientForActiveTaskTests = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
