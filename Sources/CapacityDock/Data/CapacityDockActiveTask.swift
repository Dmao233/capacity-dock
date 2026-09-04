import Foundation
import SQLite3

/// A live unit of work for the Capacity Dock detail card. Idle providers
/// return an empty list so the card does not invent a persistent empty state.
struct CapacityDockActiveTask: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
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

/// Read-only view of Cursor's local AI-code tracking database. Rows appear
/// while Composer is writing files; they are not a process list and are never
/// copied into Capacity Dock storage. Titles prefer Cursor's conversation
/// name, then the last hashed file.
struct CursorLiveEditStore: Sendable {
    let databaseURL: URL
    let conversationSearchURL: URL

    init(databaseURL: URL, conversationSearchURL: URL) {
        self.databaseURL = databaseURL
        self.conversationSearchURL = conversationSearchURL
    }

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(
            databaseURL: Self.defaultDatabaseURL(home: home),
            conversationSearchURL: Self.defaultConversationSearchURL(home: home)
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

    func tasks(since cutoff: Date) throws -> [CapacityDockActiveTask] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        let cutoffMs = Int64(cutoff.timeIntervalSince1970 * 1000)
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

        var rows: [(id: String, fileName: String?)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let conversation = sqlite3_column_text(statement, 0).map({ String(cString: $0) }),
                  !conversation.isEmpty else { continue }
            rows.append((
                id: conversation,
                fileName: sqlite3_column_text(statement, 1).map { String(cString: $0) }
            ))
        }

        let summaryTitles = Self.titles(
            for: rows.map(\.id),
            database: database,
            sql: "SELECT title FROM conversation_summaries WHERE conversationId = ? LIMIT 1;"
        )
        let missing = rows.map(\.id).filter { summaryTitles[$0] == nil }
        let searchTitles = Self.titles(for: missing, databaseURL: conversationSearchURL)

        return rows.map { row in
            CapacityDockActiveTask(
                id: row.id,
                title: summaryTitles[row.id]
                    ?? searchTitles[row.id]
                    ?? Self.displayTitle(path: row.fileName)
            )
        }
    }

    static func displayTitle(path: String?) -> String {
        LiveActivityPath.fileTitle(path)
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
                ranked.append((
                    heartbeat,
                    CapacityDockActiveTask(
                        id: sessionDir.lastPathComponent,
                        title: title(for: sessionDir, cwdDir: cwdDir)
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

    private func title(for sessionDir: URL, cwdDir: URL) -> String {
        let summaryURL = sessionDir.appendingPathComponent("summary.json", isDirectory: false)
        if let data = try? Data(contentsOf: summaryURL, options: [.mappedIfSafe]),
           let summary = try? JSONDecoder().decode(GrokSessionSummary.self, from: data) {
            if let title = LiveActivityPath.nonEmpty(summary.generatedTitle)
                ?? LiveActivityPath.nonEmpty(summary.sessionSummary) {
                return title
            }
            if let cwd = summary.info?.cwd {
                return LiveActivityPath.workspaceTitle(cwd)
            }
        }
        if let decoded = cwdDir.lastPathComponent.removingPercentEncoding {
            return LiveActivityPath.workspaceTitle(decoded)
        }
        return "Agent"
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

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        sessionsURL = home.appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    func tasks(since cutoff: Date) -> [CapacityDockActiveTask] {
        var ranked: [(Date, CapacityDockActiveTask)] = []
        for file in numericTreeFiles(root: sessionsURL, remainingDepth: 4) {
            guard file.pathExtension == "jsonl" else { continue }
            guard let modified = LiveActivityPath.modificationDate(file), modified >= cutoff else { continue }
            ranked.append((
                modified,
                CapacityDockActiveTask(
                    id: file.lastPathComponent,
                    title: title(for: file)
                )
            ))
        }
        return ranked.sorted { $0.0 > $1.0 }.map(\.1)
    }

    private func title(for file: URL) -> String {
        if let cwd = LiveActivityPath.firstJSONString(named: "cwd", in: file) {
            return LiveActivityPath.workspaceTitle(cwd)
        }
        return "Codex"
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
