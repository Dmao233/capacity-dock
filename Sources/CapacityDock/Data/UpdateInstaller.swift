import AppKit
import CryptoKit
import Foundation

enum UpdateInstallError: LocalizedError, Equatable {
    case missingZipAsset
    case missingChecksumAsset
    case missingChecksumEntry(String)
    case checksumMismatch
    case appNotFoundInArchive
    case versionMismatch(expected: String, found: String?)
    case invalidSignature
    case commandFailed(String)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingZipAsset:
            return NSLocalizedString("This release has no zip to install.", comment: "")
        case .missingChecksumAsset:
            return NSLocalizedString("This release has no SHA256SUMS file.", comment: "")
        case .missingChecksumEntry(let name):
            return String(format: NSLocalizedString("SHA256SUMS has no entry for %@.", comment: ""), name)
        case .checksumMismatch:
            return NSLocalizedString("The download doesn’t match its checksum. Nothing was changed.", comment: "")
        case .appNotFoundInArchive:
            return NSLocalizedString("The zip doesn’t contain CapacityDock.app.", comment: "")
        case .versionMismatch(let expected, let found):
            return String(
                format: NSLocalizedString("The downloaded app is version %@, expected %@.", comment: ""),
                found ?? "?",
                expected
            )
        case .invalidSignature:
            return NSLocalizedString("The downloaded app’s code signature is invalid.", comment: "")
        case .commandFailed(let message), .installFailed(let message):
            return message
        }
    }
}

/// Where the running copy lives and whether it can replace itself.
enum UpdateInstallLocation: Equatable {
    case installable(URL)
    /// Running from a build directory, a translocated path, or a folder the
    /// user can't write to — fall back to the release page.
    case unsupported(String)

    static func resolve(
        bundleURL: URL,
        fileManager: FileManager = .default
    ) -> UpdateInstallLocation {
        let bundleURL = bundleURL.standardizedFileURL
        guard bundleURL.pathExtension == "app" else {
            return .unsupported(NSLocalizedString("Not running from an app bundle.", comment: ""))
        }
        if bundleURL.path.contains("/AppTranslocation/") {
            return .unsupported(NSLocalizedString("macOS is running this copy from a quarantine location. Move it to Applications first.", comment: ""))
        }
        let parent = bundleURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: parent.path) else {
            return .unsupported(NSLocalizedString("No write permission for the app’s folder.", comment: ""))
        }
        return .installable(bundleURL)
    }
}

enum UpdateChecksums {
    /// Parses `shasum -a 256` output: `<hex>  <name>` or `<hex> *<name>`.
    static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(where: \.isWhitespace) else { continue }
            let hash = trimmed[..<space].lowercased()
            guard hash.count == 64, hash.allSatisfy(\.isHexDigit) else { continue }
            var name = trimmed[space...].trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("*") { name.removeFirst() }
            guard !name.isEmpty else { continue }
            result[name] = hash
        }
        return result
    }

    static func expectedHash(for fileName: String, in text: String) throws -> String {
        guard let hash = parse(text)[fileName] else {
            throw UpdateInstallError.missingChecksumEntry(fileName)
        }
        return hash
    }

    static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// File-system steps of an update. Every path is passed in so tests can run
/// against temporary directories.
enum UpdateInstallSteps {
    static let appName = "CapacityDock.app"

    /// Verifies the zip against SHA256SUMS, extracts it into `workDirectory`,
    /// and checks the bundle version. Returns the extracted app. Never touches
    /// the installed copy.
    static func stage(
        zipURL: URL,
        zipName: String,
        checksums: String,
        expectedVersion: String,
        workDirectory: URL,
        verifySignature: Bool = true
    ) throws -> URL {
        let expected = try UpdateChecksums.expectedHash(for: zipName, in: checksums)
        guard try UpdateChecksums.sha256(of: zipURL) == expected else {
            throw UpdateInstallError.checksumMismatch
        }

        let extractDirectory = workDirectory.appendingPathComponent("extracted", isDirectory: true)
        try? FileManager.default.removeItem(at: extractDirectory)
        try FileManager.default.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", zipURL.path, extractDirectory.path])

        let app = extractDirectory.appendingPathComponent(appName, isDirectory: true)
        try verifyBundle(at: app, expectedVersion: expectedVersion)
        if verifySignature {
            do {
                try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
            } catch {
                throw UpdateInstallError.invalidSignature
            }
        }
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        return app
    }

    static func verifyBundle(at app: URL, expectedVersion: String) throws {
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            throw UpdateInstallError.appNotFoundInArchive
        }
        let data = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let found = (plist?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let found, AppVersion.normalize(found) == AppVersion.normalize(expectedVersion) else {
            throw UpdateInstallError.versionMismatch(expected: expectedVersion, found: found)
        }
    }

    /// Replaces `installedApp` with `newApp`. The old copy is first renamed
    /// inside its own folder (which works even when the bundle itself is
    /// root-owned from the pkg installer), and restored if the move fails.
    static func replace(
        installedApp: URL,
        with newApp: URL,
        fileManager: FileManager = .default
    ) throws {
        let parent = installedApp.deletingLastPathComponent()
        let backup = parent.appendingPathComponent(
            ".\(installedApp.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).old.app",
            isDirectory: true
        )
        let hadInstalledCopy = fileManager.fileExists(atPath: installedApp.path)
        if hadInstalledCopy {
            do {
                try fileManager.moveItem(at: installedApp, to: backup)
            } catch {
                throw UpdateInstallError.installFailed(error.localizedDescription)
            }
        }
        do {
            try fileManager.moveItem(at: newApp, to: installedApp)
        } catch {
            if hadInstalledCopy {
                try? fileManager.removeItem(at: installedApp)
                try? fileManager.moveItem(at: backup, to: installedApp)
            }
            throw UpdateInstallError.installFailed(error.localizedDescription)
        }
        guard hadInstalledCopy else { return }
        if (try? fileManager.removeItem(at: backup)) == nil {
            _ = try? fileManager.trashItem(at: backup, resultingItemURL: nil)
        }
    }

    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let name = URL(fileURLWithPath: executable).lastPathComponent
            throw UpdateInstallError.commandFailed("\(name): \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return text
    }
}

enum UpdateInstallPhase: Equatable {
    case idle
    case downloading(Double?)
    case verifying
    case installing
    case relaunching
    case failed(String)
}

/// Downloads, verifies, and installs a GitHub Release over the running app.
@MainActor @Observable
final class UpdateInstaller {
    static let shared = UpdateInstaller()

    private(set) var phase: UpdateInstallPhase = .idle
    private var installTask: Task<Void, Never>?

    var isBusy: Bool {
        switch phase {
        case .downloading, .verifying, .installing, .relaunching: return true
        case .idle, .failed: return false
        }
    }

    var location: UpdateInstallLocation {
        UpdateInstallLocation.resolve(bundleURL: Bundle.main.bundleURL)
    }

    func install(_ release: GitHubRelease) {
        guard !isBusy else { return }
        guard case .installable(let appURL) = location else { return }
        installTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.perform(release, appURL: appURL)
            } catch {
                self.phase = Task.isCancelled ? .idle : .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        installTask?.cancel()
    }

    private func perform(_ release: GitHubRelease, appURL: URL) async throws {
        guard let zip = release.zipAsset, let zipURL = URL(string: zip.browserDownloadURL) else {
            throw UpdateInstallError.missingZipAsset
        }
        guard let sums = release.sha256SumsAsset, let sumsURL = URL(string: sums.browserDownloadURL) else {
            throw UpdateInstallError.missingChecksumAsset
        }

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapacityDock-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        phase = .downloading(nil)
        let checksumsData = try await Self.fetch(sumsURL)
        let checksums = String(decoding: checksumsData, as: UTF8.self)
        let zipFile = workDirectory.appendingPathComponent(zip.name)
        try await Self.download(zipURL, to: zipFile) { [weak self] fraction in
            Task { @MainActor in
                guard let self, case .downloading = self.phase else { return }
                self.phase = .downloading(fraction)
            }
        }
        try Task.checkCancellation()

        phase = .verifying
        let version = release.version
        let stagedApp = try await Task.detached {
            try UpdateInstallSteps.stage(
                zipURL: zipFile,
                zipName: zip.name,
                checksums: checksums,
                expectedVersion: version,
                workDirectory: workDirectory
            )
        }.value
        try Task.checkCancellation()

        phase = .installing
        try await Task.detached {
            try UpdateInstallSteps.replace(installedApp: appURL, with: stagedApp)
        }.value

        phase = .relaunching
        try Self.relaunch(appURL)
        NSApp.terminate(nil)
    }

    private nonisolated static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(
            "CapacityDock/\(AppVersion.current) (+https://github.com/Dmao233/capacity-dock)",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 30
        return request
    }

    private nonisolated static func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request(url))
        try checkStatus(response)
        return data
    }

    private nonisolated static func checkStatus(_ response: URLResponse?) throws {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw UpdateInstallError.commandFailed("GitHub returned \(http.statusCode).")
        }
    }

    private nonisolated static func download(
        _ url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        let box = DownloadTaskBox()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = URLSession.shared.downloadTask(with: request(url)) { tempURL, response, error in
                    box.observation?.invalidate()
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    do {
                        try checkStatus(response)
                        guard let tempURL else { throw URLError(.cannotCreateFile) }
                        try? FileManager.default.removeItem(at: destination)
                        try FileManager.default.moveItem(at: tempURL, to: destination)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                box.observation = task.progress.observe(\.fractionCompleted) { value, _ in
                    progress(value.totalUnitCount > 0 ? value.fractionCompleted : nil)
                }
                box.task = task
                task.resume()
            }
        } onCancel: {
            box.task?.cancel()
        }
    }

    /// Waits for this process to exit, then opens the replaced bundle, so the
    /// old and new copies never run at the same time.
    private nonisolated static func relaunch(_ appURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"",
            "sh",
            String(ProcessInfo.processInfo.processIdentifier),
            appURL.path
        ]
        try process.run()
    }
}

private final class DownloadTaskBox: @unchecked Sendable {
    var task: URLSessionDownloadTask?
    var observation: NSKeyValueObservation?
}
