import Foundation
import SQLite3

/// A live unit of work for the Capacity Dock detail card. Idle providers
/// return an empty list so the card does not invent a persistent empty state.
struct CapacityDockActiveTask: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let workspace: String?

    init(id: String, title: String, workspace: String? = nil) {
        self.id = id
        self.title = title
        let place = LiveActivityPath.displayWorkspace(workspace)
        self.workspace = place == title ? nil : place
    }
}

enum CapacityDockActiveTaskSnapshot {
    static let liveWindow: TimeInterval = 90
    static let maxTasks = 3

    struct Deps: Sendable {
        var now: @Sendable () -> Date
        var loadTasks: @Sendable (_ providerID: String, _ now: Date) -> [CapacityDockActiveTask]

        static let live = Deps(
            now: Date.init,
            loadTasks: { id, now in
                CapacityDockLiveActivity.tasks(
                    providerID: id,
                    since: now.addingTimeInterval(-liveWindow)
                )
            }
        )
    }

    static func tasks(
        for provider: CapacityDockProvider,
        deps: Deps = .live
    ) -> [CapacityDockActiveTask] {
        Array(deps.loadTasks(provider.id, deps.now()).prefix(maxTasks))
    }
}

/// Provider-scoped live activity. Each adapter is a cheap local mtime/SQLite
/// probe; nothing is copied into Capacity Dock storage.
enum CapacityDockLiveActivity {
    static func tasks(
        providerID: String,
        since: Date,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [CapacityDockActiveTask] {
        switch providerID {
        case "cursor":
            return (try? CursorLiveEditStore(home: home).tasks(since: since)) ?? []
        case "grok":
            return GrokLiveSessionStore(home: home).tasks(since: since)
        case "codex":
            return CodexLiveSessionStore(home: home).tasks(since: since)
        case "claude":
            return ClaudeLiveSessionStore(home: home).tasks(since: since)
        case "gemini":
            return RecentTranscriptStore(
                roots: [home.appendingPathComponent(".gemini/tmp", isDirectory: true)],
                maxDepth: 2
            ).tasks(since: since)
        case "antigravity":
            return RecentTranscriptStore(
                roots: [
                    home.appendingPathComponent(".gemini/antigravity/conversations", isDirectory: true),
                    home.appendingPathComponent(".gemini/antigravity-cli/conversations", isDirectory: true),
                    home.appendingPathComponent(".gemini/antigravity-ide/conversations", isDirectory: true)
                ],
                maxDepth: 2
            ).tasks(since: since)
        case "copilot":
            return RecentTranscriptStore(
                roots: [
                    home.appendingPathComponent(".copilot/session-state", isDirectory: true),
                    home.appendingPathComponent(
                        "Library/Application Support/Code/User/globalStorage/github.copilot-chat",
                        isDirectory: true
                    )
                ],
                maxDepth: 2
            ).tasks(since: since)
        case "kimi":
            return RecentTranscriptStore(
                roots: [home.appendingPathComponent(".kimi/sessions", isDirectory: true)],
                maxDepth: 2
            ).tasks(since: since)
        default:
            return []
        }
    }
}

/// Read-only view of Cursor's local activity. Subagents follow Cursor's
/// "Working N" (`unfinishedRunAt` + `subagentInfo`). Parent chats need a
/// live generating bubble or a loading tool header — leftover parent
/// `unfinishedRunAt` is not enough. Titles prefer the running composer name.
struct CursorLiveEditStore: Sendable {
    let databaseURL: URL
    let conversationSearchURL: URL
    let composerHeadersURL: URL

    init(databaseURL: URL, conversationSearchURL: URL, composerHeadersURL: URL) {
        self.databaseURL = databaseURL
        self.conversationSearchURL = conversationSearchURL
        self.composerHeadersURL = composerHeadersURL
    }

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(
            databaseURL: Self.defaultDatabaseURL(home: home),
            conversationSearchURL: Self.defaultConversationSearchURL(home: home),
            composerHeadersURL: Self.defaultComposerHeadersURL(home: home)
        )
    }

    static func defaultDatabaseURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent("ai-tracking", isDirectory: true)
            .appendingPathComponent("ai-code-tracking.db", isDirectory: false)
    }

    static func defaultConversationSearchURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage", isDirectory: true)
            .appendingPathComponent("conversation-search.db", isDirectory: false)
    }

    static func defaultComposerHeadersURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage", isDirectory: true)
            .appendingPathComponent("state.vscdb", isDirectory: false)
    }

    func tasks(since cutoff: Date) throws -> [CapacityDockActiveTask] {
        let cutoffMs = Int64(cutoff.timeIntervalSince1970 * 1000)
        let hashes = try liveHashes(since: cutoffMs)
        let chats = liveConversations(since: cutoffMs)
        let headers = unfinishedHeaders()
        var candidates: Set<String> = Set(headers.map(\.composerID))
        for hash in hashes { candidates.insert(hash.id) }
        for chat in chats { candidates.insert(chat.id) }
        let running = generatingComposers(ids: candidates, unfinished: headers, cutoffMs: cutoffMs)
        if running.isEmpty { return [] }

        var ranked: [String: RankedRow] = [:]
        for hash in hashes {
            ranked[hash.id] = RankedRow(timestamp: hash.timestamp, fileName: hash.fileName)
        }
        for chat in chats {
            if var existing = ranked[chat.id] {
                existing.timestamp = max(existing.timestamp, chat.timestamp)
                existing.searchTitle = chat.title
                ranked[chat.id] = existing
            } else {
                ranked[chat.id] = RankedRow(timestamp: chat.timestamp, searchTitle: chat.title)
            }
        }
        for run in running {
            if var existing = ranked[run.parentID] {
                existing.timestamp = max(existing.timestamp, run.timestamp)
                if let title = run.title {
                    existing.runningTitle = title
                }
                if existing.workspace == nil {
                    existing.workspace = run.workspace
                }
                ranked[run.parentID] = existing
            } else {
                ranked[run.parentID] = RankedRow(
                    timestamp: run.timestamp,
                    runningTitle: run.title,
                    workspace: run.workspace
                )
            }
        }
        ranked = ranked.filter { id, _ in running.contains { $0.parentID == id } }

        let missingTitles = ranked.compactMap { id, row in
            row.runningTitle == nil && row.searchTitle == nil ? id : nil
        }
        let lookedUpTitles = Self.titles(for: missingTitles, databaseURL: conversationSearchURL)
        for (id, title) in lookedUpTitles {
            guard var row = ranked[id] else { continue }
            row.searchTitle = title
            ranked[id] = row
        }

        let ids = ranked.keys.sorted { lhs, rhs in
            (ranked[lhs]?.timestamp ?? 0) > (ranked[rhs]?.timestamp ?? 0)
        }
        let summaryTitles = trackingSummaryTitles(for: ids)

        return ids.compactMap { id in
            guard let row = ranked[id] else { return nil }
            let fileTitle = LiveActivityPath.nonEmpty(row.fileName).map {
                URL(fileURLWithPath: $0).lastPathComponent
            }
            guard let title = row.runningTitle ?? summaryTitles[id] ?? row.searchTitle ?? fileTitle else {
                return nil
            }
            return CapacityDockActiveTask(id: id, title: title, workspace: row.workspace)
        }
    }

    static func displayTitle(path: String?) -> String {
        LiveActivityPath.fileTitle(path)
    }

    private struct RankedRow {
        var timestamp: Int64
        var fileName: String? = nil
        var searchTitle: String? = nil
        var runningTitle: String? = nil
        var workspace: String? = nil
    }

    private struct UnfinishedComposer {
        var parentID: String
        var title: String?
        var timestamp: Int64
        var workspace: String? = nil
    }

    private struct UnfinishedHeader {
        var composerID: String
        var parentID: String
        var title: String?
        var timestamp: Int64
        var checkpointAt: Int64?
        var workspace: String?
        var isSubagent: Bool
    }

    /// Cursor's "Working N" is unfinished subagent headers. Parent chats keep
    /// `unfinishedRunAt` after a turn, so leftover flags are not enough.
    /// A parent is live when its header checkpoint is still moving, or when
    /// `composerData` shows a generating bubble / in-flight tool.
    private func unfinishedHeaders() -> [UnfinishedHeader] {
        guard FileManager.default.fileExists(atPath: composerHeadersURL.path) else { return [] }
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(composerHeadersURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK else {
            sqlite3_close(database)
            return []
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 1000)

        var statement: OpaquePointer?
        let sql = """
        SELECT composerId, value
        FROM composerHeaders
        WHERE value LIKE '%unfinishedRunAt%';
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var rows: [UnfinishedHeader] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = sqlite3_column_text(statement, 0).map({ String(cString: $0) }),
                  !id.isEmpty,
                  let raw = sqlite3_column_text(statement, 1).map({ String(cString: $0) }),
                  let header = Self.parseUnfinishedHeader(id: id, value: raw)
            else { continue }
            rows.append(header)
        }
        return rows
    }

    private static func parseUnfinishedHeader(
        id: String,
        value: String
    ) -> UnfinishedHeader? {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runAt = int64(object["unfinishedRunAt"])
        else { return nil }
        let info = object["subagentInfo"] as? [String: Any]
        let parent = LiveActivityPath.nonEmpty(info?["rootParentConversationId"] as? String)
            ?? LiveActivityPath.nonEmpty(info?["parentComposerId"] as? String)
            ?? id
        let checkpoint = int64(object["conversationCheckpointLastUpdatedAt"])
        return UnfinishedHeader(
            composerID: id,
            parentID: parent,
            title: LiveActivityPath.nonEmpty(object["name"] as? String),
            timestamp: max(runAt, checkpoint ?? runAt),
            checkpointAt: checkpoint,
            workspace: LiveActivityPath.composerWorkspace(object),
            isSubagent: info != nil
        )
    }

    private func generatingComposers(
        ids: Set<String>,
        unfinished: [UnfinishedHeader],
        cutoffMs: Int64
    ) -> [UnfinishedComposer] {
        var latest: [String: UnfinishedComposer] = [:]
        func add(_ run: UnfinishedComposer) {
            if let existing = latest[run.parentID], existing.timestamp >= run.timestamp {
                return
            }
            latest[run.parentID] = run
        }
        var resolved = Set<String>()
        for header in unfinished {
            let parentStillWriting = !header.isSubagent
                && (header.checkpointAt ?? 0) >= cutoffMs
            guard header.isSubagent || parentStillWriting else { continue }
            add(UnfinishedComposer(
                parentID: header.parentID,
                title: header.title,
                timestamp: header.timestamp,
                workspace: header.workspace
            ))
            resolved.insert(header.composerID)
        }
        let pending = ids.subtracting(resolved)
        for id in pending {
            guard let object = composerData(id), Self.isGenerating(object) else { continue }
            add(Self.parseRunningComposer(id: id, object: object))
        }
        return Array(latest.values)
    }

    private func composerData(_ id: String) -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: composerHeadersURL.path) else { return nil }
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(composerHeadersURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK else {
            sqlite3_close(database)
            return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 1000)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT value FROM cursorDiskKV WHERE key = ? LIMIT 1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        let key = "composerData:\(id)"
        sqlite3_bind_text(statement, 1, key, -1, sqliteTransientForLiveActivity)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let raw = sqlite3_column_text(statement, 0).map({ String(cString: $0) }),
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    static func isGenerating(_ object: [String: Any]) -> Bool {
        if let bubbles = object["generatingBubbleIds"] as? [Any], !bubbles.isEmpty {
            return true
        }
        if object["unfinishedRunAt"] != nil, hasInProgressTodo(object) {
            return true
        }
        guard let headers = object["fullConversationHeadersOnly"] as? [[String: Any]] else {
            return false
        }
        return headers.suffix(8).contains(where: isActiveHeader)
    }

    private static func hasInProgressTodo(_ object: [String: Any]) -> Bool {
        guard let todos = object["todos"] as? [[String: Any]] else { return false }
        return todos.contains { todo in
            let status = (todo["status"] as? String)?.lowercased()
            return status == "in_progress" || status == "in-progress"
        }
    }

    private static func isActiveHeader(_ header: [String: Any]) -> Bool {
        guard let grouping = header["grouping"] as? [String: Any] else { return false }
        let tool = (grouping["toolFormerStatus"] as? String)?.lowercased()
        let shell = (grouping["shellStatus"] as? String)?.lowercased()
        return tool == "loading" || tool == "running" || shell == "running"
    }

    private static func parseRunningComposer(id: String, object: [String: Any]) -> UnfinishedComposer {
        let info = object["subagentInfo"] as? [String: Any]
        let parent = LiveActivityPath.nonEmpty(info?["rootParentConversationId"] as? String)
            ?? LiveActivityPath.nonEmpty(info?["parentComposerId"] as? String)
            ?? id
        let title = LiveActivityPath.nonEmpty(object["name"] as? String)
        let timestamp = int64(object["lastUpdatedAt"])
            ?? int64(object["conversationCheckpointLastUpdatedAt"])
            ?? int64(object["unfinishedRunAt"])
            ?? 0
        return UnfinishedComposer(
            parentID: parent,
            title: title,
            timestamp: timestamp,
            workspace: LiveActivityPath.composerWorkspace(object)
        )
    }

    private static func int64(_ raw: Any?) -> Int64? {
        switch raw {
        case let value as Int64:
            return value
        case let value as Int:
            return Int64(value)
        case let value as Double:
            return Int64(value)
        case let value as NSNumber:
            return value.int64Value
        default:
            return nil
        }
    }

    private func liveHashes(since cutoffMs: Int64) throws -> [(id: String, fileName: String?, timestamp: Int64)] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK else {
            sqlite3_close(database)
            throw CursorLiveEditStoreError.unreadable
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)

        var statement: OpaquePointer?
        let sql = """
        SELECT conversationId, fileName, MAX(timestamp) AS ts
        FROM ai_code_hashes
        WHERE timestamp >= ?
        GROUP BY conversationId
        ORDER BY ts DESC;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CursorLiveEditStoreError.unreadable
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, cutoffMs)

        var rows: [(id: String, fileName: String?, timestamp: Int64)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let conversation = sqlite3_column_text(statement, 0).map({ String(cString: $0) }),
                  !conversation.isEmpty else { continue }
            rows.append((
                id: conversation,
                fileName: sqlite3_column_text(statement, 1).map { String(cString: $0) },
                timestamp: sqlite3_column_int64(statement, 2)
            ))
        }
        return rows
    }

    private func liveConversations(since cutoffMs: Int64) -> [(id: String, title: String?, timestamp: Int64)] {
        Self.liveConversations(since: cutoffMs, databaseURL: conversationSearchURL)
    }

    private func trackingSummaryTitles(for ids: [String]) -> [String: String] {
        guard !ids.isEmpty, FileManager.default.fileExists(atPath: databaseURL.path) else { return [:] }
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK else {
            sqlite3_close(database)
            return [:]
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)
        return Self.titles(
            for: ids,
            database: database,
            sql: "SELECT title FROM conversation_summaries WHERE conversationId = ? LIMIT 1;"
        )
    }

    private static func liveConversations(
        since cutoffMs: Int64,
        databaseURL: URL
    ) -> [(id: String, title: String?, timestamp: Int64)] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK else {
            sqlite3_close(database)
            return []
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)

        var statement: OpaquePointer?
        let sql = """
        SELECT id, title, updated_at
        FROM conversations
        WHERE updated_at >= ?
        ORDER BY updated_at DESC;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, cutoffMs)

        var rows: [(id: String, title: String?, timestamp: Int64)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = sqlite3_column_text(statement, 0).map({ String(cString: $0) }),
                  !id.isEmpty else { continue }
            rows.append((
                id: id,
                title: LiveActivityPath.nonEmpty(
                    sqlite3_column_text(statement, 1).map { String(cString: $0) }
                ),
                timestamp: sqlite3_column_int64(statement, 2)
            ))
        }
        return rows
    }

    private static func titles(
        for ids: [String],
        databaseURL: URL
    ) -> [String: String] {
        guard !ids.isEmpty, FileManager.default.fileExists(atPath: databaseURL.path) else { return [:] }
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK else {
            sqlite3_close(database)
            return [:]
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)
        return titles(
            for: ids,
            database: database,
            sql: "SELECT title FROM conversations WHERE id = ? LIMIT 1;"
        )
    }

    private static func titles(
        for ids: [String],
        database: OpaquePointer?,
        sql: String
    ) -> [String: String] {
        guard let database, !ids.isEmpty else { return [:] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(statement) }

        var found: [String: String] = [:]
        for id in ids {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_text(statement, 1, id, -1, sqliteTransientForLiveActivity)
            guard sqlite3_step(statement) == SQLITE_ROW,
                  let title = LiveActivityPath.nonEmpty(
                    sqlite3_column_text(statement, 0).map { String(cString: $0) }
                  ) else { continue }
            found[id] = title
        }
        return found
    }
}

private let sqliteTransientForLiveActivity = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct GrokLiveSessionStore {
    let sessionsURL: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        sessionsURL = home.appendingPathComponent(".grok/sessions", isDirectory: true)
    }

    func tasks(since cutoff: Date) -> [CapacityDockActiveTask] {
        guard let cwdDirs = try? FileManager.default.contentsOfDirectory(
            at: sessionsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var ranked: [(Date, CapacityDockActiveTask)] = []
        for cwdDir in cwdDirs where LiveActivityPath.isDirectory(cwdDir) {
            guard let sessionDirs = try? FileManager.default.contentsOfDirectory(
                at: cwdDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for sessionDir in sessionDirs where LiveActivityPath.isDirectory(sessionDir) {
                guard let heartbeat = heartbeatDate(in: sessionDir), heartbeat >= cutoff else { continue }
                let labeled = title(for: sessionDir, cwdDir: cwdDir)
                ranked.append((
                    heartbeat,
                    CapacityDockActiveTask(
                        id: sessionDir.lastPathComponent,
                        title: labeled.title,
                        workspace: labeled.workspace
                    )
                ))
            }
        }
        return ranked.sorted { $0.0 > $1.0 }.map(\.1)
    }

    private func heartbeatDate(in sessionDir: URL) -> Date? {
        let names = ["updates.jsonl", "events.jsonl", "chat_history.jsonl", "summary.json"]
        return names.compactMap { name in
            LiveActivityPath.modificationDate(
                sessionDir.appendingPathComponent(name, isDirectory: false)
            )
        }.max()
    }

    private func title(for sessionDir: URL, cwdDir: URL) -> (title: String, workspace: String?) {
        let folderWorkspace = cwdDir.lastPathComponent.removingPercentEncoding
            .flatMap(LiveActivityPath.displayWorkspace)
        let summaryURL = sessionDir.appendingPathComponent("summary.json", isDirectory: false)
        if let data = try? Data(contentsOf: summaryURL, options: [.mappedIfSafe]),
           let summary = try? JSONDecoder().decode(GrokSessionSummary.self, from: data) {
            let cwdWorkspace = summary.info?.cwd.flatMap(LiveActivityPath.displayWorkspace)
            if let title = LiveActivityPath.nonEmpty(summary.generatedTitle)
                ?? LiveActivityPath.nonEmpty(summary.sessionSummary) {
                return (title, cwdWorkspace ?? folderWorkspace)
            }
            if let workspace = cwdWorkspace ?? folderWorkspace {
                return (workspace, nil)
            }
        }
        if let workspace = folderWorkspace {
            return (workspace, nil)
        }
        return ("Agent", nil)
    }

    private struct GrokSessionSummary: Decodable {
        let generatedTitle: String?
        let sessionSummary: String?
        let info: Info?

        enum CodingKeys: String, CodingKey {
            case generatedTitle = "generated_title"
            case sessionSummary = "session_summary"
            case info
        }

        struct Info: Decodable {
            let cwd: String?
        }
    }
}

struct CodexLiveSessionStore {
    let sessionsURL: URL
    let threadDatabaseURL: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        sessionsURL = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        threadDatabaseURL = home.appendingPathComponent(".codex/state_5.sqlite", isDirectory: false)
    }

    func tasks(since cutoff: Date) -> [CapacityDockActiveTask] {
        var ranked: [(Date, CapacityDockActiveTask)] = []
        let names = threadNames()
        for file in numericTreeFiles(root: sessionsURL, remainingDepth: 4) {
            guard file.pathExtension == "jsonl" else { continue }
            guard let modified = LiveActivityPath.modificationDate(file), modified >= cutoff else { continue }
            let labeled = title(for: file, names: names)
            ranked.append((
                modified,
                CapacityDockActiveTask(
                    id: file.lastPathComponent,
                    title: labeled.title,
                    workspace: labeled.workspace
                )
            ))
        }
        return ranked.sorted { $0.0 > $1.0 }.map(\.1)
    }

    private func title(for file: URL, names: [String: String]) -> (title: String, workspace: String?) {
        let workspace = LiveActivityPath.firstJSONString(named: "cwd", in: file)
            .flatMap(LiveActivityPath.displayWorkspace)
        let sessionID = Self.sessionID(fromRollout: file.lastPathComponent)
        let thread = sessionID.flatMap { names[$0] } ?? names[file.path]
        if let thread {
            return (thread, workspace)
        }
        return (workspace ?? "Codex", nil)
    }

    static func sessionID(fromRollout filename: String) -> String? {
        let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        guard let range = stem.range(
            of: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#,
            options: .regularExpression
        ) else {
            return nil
        }
        return String(stem[range])
    }

    private func threadNames() -> [String: String] {
        guard FileManager.default.fileExists(atPath: threadDatabaseURL.path) else { return [:] }
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(threadDatabaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK else {
            sqlite3_close(database)
            return [:]
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 1000)

        var statement: OpaquePointer?
        let sql = "SELECT id, rollout_path, name FROM threads WHERE name IS NOT NULL AND name != '';"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(statement) }

        var names: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let name = LiveActivityPath.nonEmpty(
                sqlite3_column_text(statement, 2).map { String(cString: $0) }
            ) else { continue }
            if let id = sqlite3_column_text(statement, 0).map({ String(cString: $0) }) {
                names[id] = name
            }
            if let path = sqlite3_column_text(statement, 1).map({ String(cString: $0) }) {
                names[path] = name
            }
        }
        return names
    }

    private func numericTreeFiles(root: URL, remainingDepth: Int) -> [URL] {
        guard remainingDepth > 0,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }
        if remainingDepth == 1 {
            return entries.filter { !LiveActivityPath.isDirectory($0) }
        }
        return entries.flatMap { entry -> [URL] in
            guard LiveActivityPath.isDirectory(entry),
                  entry.lastPathComponent.allSatisfy(\.isNumber) else { return [] }
            return numericTreeFiles(root: entry, remainingDepth: remainingDepth - 1)
        }
    }
}

struct ClaudeLiveSessionStore {
    let roots: [URL]

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        roots = [
            home.appendingPathComponent(".claude/projects", isDirectory: true),
            home.appendingPathComponent(
                "Library/Application Support/Claude/local-agent-mode-sessions",
                isDirectory: true
            )
        ]
    }

    func tasks(since cutoff: Date) -> [CapacityDockActiveTask] {
        var ranked: [(Date, CapacityDockActiveTask)] = []
        for root in roots {
            guard let projects = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for project in projects where LiveActivityPath.isDirectory(project) {
                guard let files = try? FileManager.default.contentsOfDirectory(
                    at: project,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for file in files where file.pathExtension == "jsonl" {
                    guard let modified = LiveActivityPath.modificationDate(file),
                          modified >= cutoff else { continue }
                    ranked.append((
                        modified,
                        CapacityDockActiveTask(
                            id: file.lastPathComponent,
                            title: LiveActivityPath.workspaceTitle(
                                LiveActivityPath.claudeProjectPath(project.lastPathComponent)
                            )
                        )
                    ))
                }
            }
        }
        return ranked.sorted { $0.0 > $1.0 }.map(\.1)
    }
}

struct RecentTranscriptStore {
    let roots: [URL]
    let maxDepth: Int

    func tasks(since cutoff: Date) -> [CapacityDockActiveTask] {
        var ranked: [(Date, CapacityDockActiveTask)] = []
        for root in roots {
            collect(from: root, depth: 0, since: cutoff, into: &ranked)
        }
        return ranked.sorted { $0.0 > $1.0 }.map(\.1)
    }

    private func collect(
        from directory: URL,
        depth: Int,
        since cutoff: Date,
        into ranked: inout [(Date, CapacityDockActiveTask)]
    ) {
        guard depth <= maxDepth,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else { return }
        for entry in entries {
            if LiveActivityPath.isDirectory(entry) {
                collect(from: entry, depth: depth + 1, since: cutoff, into: &ranked)
                continue
            }
            let name = entry.lastPathComponent
            if LiveActivityPath.isIgnoredProcessName(name) { continue }
            guard let modified = LiveActivityPath.modificationDate(entry), modified >= cutoff else { continue }
            ranked.append((
                modified,
                CapacityDockActiveTask(
                    id: entry.path,
                    title: LiveActivityPath.fileTitle(name)
                )
            ))
        }
    }
}

enum LiveActivityPath {
    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func isIgnoredProcessName(_ name: String) -> Bool {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return folded.contains("electron helper") || folded.contains("crashpad")
    }

    static func fileTitle(_ path: String?) -> String {
        let raw = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return "Agent" }
        return URL(fileURLWithPath: raw).lastPathComponent
    }

    static func hierarchicalTitle(workspace: String, thread: String?) -> String {
        let place = workspace.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = thread?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.isEmpty || name == place { return place.isEmpty ? "Codex" : place }
        if place.isEmpty || place == "Codex" { return name }
        return "\(place)-\(name)"
    }

    static func displayWorkspace(_ path: String?) -> String? {
        guard let path, let name = nonEmpty(workspaceTitle(path)) else { return nil }
        if name == "Agent" || name == "Home" || name == "Codex" { return nil }
        return name
    }

    static func composerWorkspace(_ object: [String: Any]) -> String? {
        if let ident = object["workspaceIdentifier"] as? [String: Any],
           let path = uriPath(ident["uri"]) {
            return displayWorkspace(path)
        }
        if let location = object["agentLocation"] as? [String: Any],
           let environment = location["environment"] as? [String: Any],
           let path = uriPath(environment["uri"]) {
            return displayWorkspace(path)
        }
        if let repos = object["trackedGitRepos"] as? [[String: Any]],
           let path = repos.first?["repoPath"] as? String {
            return displayWorkspace(path)
        }
        return nil
    }

    private static func uriPath(_ raw: Any?) -> String? {
        if let path = raw as? String { return path }
        guard let uri = raw as? [String: Any] else { return nil }
        return (uri["fsPath"] as? String) ?? (uri["path"] as? String)
    }

    static func workspaceTitle(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Agent" }
        let url = URL(fileURLWithPath: trimmed)
        let last = url.lastPathComponent
        if last == "lu" || last == NSUserName() || trimmed == NSHomeDirectory() {
            return "Home"
        }
        return last.isEmpty ? "Agent" : last
    }

    static func claudeProjectPath(_ folder: String) -> String {
        var value = folder
        if value.hasPrefix("-") { value.removeFirst() }
        return "/" + value.replacingOccurrences(of: "-", with: "/")
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    static func firstJSONString(named key: String, in file: URL, maxBytes: Int = 32_768) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: maxBytes)
        guard let chunk = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii) else { return nil }
        let needle = "\"\(key)\":\""
        guard let start = chunk.range(of: needle) else { return nil }
        var result = ""
        var escaping = false
        for character in chunk[start.upperBound...] {
            if escaping {
                result.append(character)
                escaping = false
                continue
            }
            if character == "\\" {
                escaping = true
                continue
            }
            if character == "\"" {
                return result.isEmpty ? nil : result
            }
            result.append(character)
            if result.count > 512 { return nil }
        }
        return nil
    }
}

private enum CursorLiveEditStoreError: Error {
    case unreadable
}
