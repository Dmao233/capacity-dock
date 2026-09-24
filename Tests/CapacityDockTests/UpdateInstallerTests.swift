import Foundation
import Testing
@testable import CapacityDock

@Suite("Update installer")
struct UpdateInstallerTests {
    private static let zipHash = String(repeating: "ab", count: 32)

    @Test("SHA256SUMS lines map file names to hashes")
    func parsesChecksums() {
        let text = """
        \(String(repeating: "0", count: 64))  CapacityDock-0.3.7.pkg
        \(Self.zipHash.uppercased()) *CapacityDock-0.3.7.zip
        not-a-hash  junk.txt

        """
        let sums = UpdateChecksums.parse(text)
        #expect(sums.count == 2)
        #expect(sums["CapacityDock-0.3.7.zip"] == Self.zipHash)
        #expect(sums["CapacityDock-0.3.7.pkg"] == String(repeating: "0", count: 64))
    }

    @Test("missing zip entry is an error")
    func missingChecksumEntry() {
        let text = "\(Self.zipHash)  CapacityDock-0.3.6.zip\n"
        #expect(throws: UpdateInstallError.missingChecksumEntry("CapacityDock-0.3.7.zip")) {
            try UpdateChecksums.expectedHash(for: "CapacityDock-0.3.7.zip", in: text)
        }
    }

    @Test("release JSON exposes the SHA256SUMS asset")
    func decodesChecksumAsset() throws {
        let json = """
        {
          "tag_name": "v0.3.7",
          "html_url": "https://github.com/Dmao233/capacity-dock/releases/tag/v0.3.7",
          "assets": [
            { "name": "CapacityDock-0.3.7.zip", "browser_download_url": "https://example.com/z" },
            { "name": "SHA256SUMS", "browser_download_url": "https://example.com/s" }
          ]
        }
        """.data(using: .utf8)!
        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        #expect(release.sha256SumsAsset?.browserDownloadURL == "https://example.com/s")
        #expect(release.zipAsset?.name == "CapacityDock-0.3.7.zip")
    }

    @Test("staging accepts a matching zip and version")
    func stagesMatchingZip() throws {
        let fixture = try Fixture(version: "0.3.7")
        defer { fixture.cleanUp() }
        let app = try UpdateInstallSteps.stage(
            zipURL: fixture.zip,
            zipName: fixture.zip.lastPathComponent,
            checksums: fixture.checksums,
            expectedVersion: "v0.3.7",
            workDirectory: fixture.work,
            verifySignature: false
        )
        #expect(app.lastPathComponent == "CapacityDock.app")
        #expect(FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/MacOS/CapacityDock").path))
    }

    @Test("staging rejects a version that doesn’t match the release")
    func rejectsVersionMismatch() throws {
        let fixture = try Fixture(version: "0.3.6")
        defer { fixture.cleanUp() }
        #expect(throws: UpdateInstallError.versionMismatch(expected: "0.3.7", found: "0.3.6")) {
            try UpdateInstallSteps.stage(
                zipURL: fixture.zip,
                zipName: fixture.zip.lastPathComponent,
                checksums: fixture.checksums,
                expectedVersion: "0.3.7",
                workDirectory: fixture.work,
                verifySignature: false
            )
        }
    }

    @Test("staging rejects a checksum mismatch before extracting")
    func rejectsChecksumMismatch() throws {
        let fixture = try Fixture(version: "0.3.7")
        defer { fixture.cleanUp() }
        #expect(throws: UpdateInstallError.checksumMismatch) {
            try UpdateInstallSteps.stage(
                zipURL: fixture.zip,
                zipName: fixture.zip.lastPathComponent,
                checksums: "\(Self.zipHash)  \(fixture.zip.lastPathComponent)\n",
                expectedVersion: "0.3.7",
                workDirectory: fixture.work,
                verifySignature: false
            )
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.work.appendingPathComponent("extracted").path))
    }

    @Test("replace swaps in the new bundle and drops the old one")
    func replacesInstalledApp() throws {
        let fixture = try Fixture(version: "0.3.7")
        defer { fixture.cleanUp() }
        let installDir = fixture.root.appendingPathComponent("Applications", isDirectory: true)
        let installed = installDir.appendingPathComponent("CapacityDock.app", isDirectory: true)
        try Fixture.makeApp(at: installed, version: "0.3.6")
        let staged = try UpdateInstallSteps.stage(
            zipURL: fixture.zip,
            zipName: fixture.zip.lastPathComponent,
            checksums: fixture.checksums,
            expectedVersion: "0.3.7",
            workDirectory: fixture.work,
            verifySignature: false
        )

        try UpdateInstallSteps.replace(installedApp: installed, with: staged)

        try UpdateInstallSteps.verifyBundle(at: installed, expectedVersion: "0.3.7")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: installDir.path)
        #expect(leftovers == ["CapacityDock.app"])
    }

    @Test("failed replace restores the installed app")
    func restoresOnFailure() throws {
        let fixture = try Fixture(version: "0.3.7")
        defer { fixture.cleanUp() }
        let installDir = fixture.root.appendingPathComponent("Applications", isDirectory: true)
        let installed = installDir.appendingPathComponent("CapacityDock.app", isDirectory: true)
        try Fixture.makeApp(at: installed, version: "0.3.6")
        let missing = fixture.root.appendingPathComponent("missing/CapacityDock.app")

        #expect(throws: UpdateInstallError.self) {
            try UpdateInstallSteps.replace(installedApp: installed, with: missing)
        }
        try UpdateInstallSteps.verifyBundle(at: installed, expectedVersion: "0.3.6")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: installDir.path)
        #expect(leftovers == ["CapacityDock.app"])
    }

    @Test("unwritable or non-bundle locations fall back to the release page")
    func resolvesLocation() throws {
        let fixture = try Fixture(version: "0.3.7")
        defer { fixture.cleanUp() }
        let readOnly = fixture.root.appendingPathComponent("ReadOnly", isDirectory: true)
        try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnly.path) }

        let writable = fixture.root.appendingPathComponent("CapacityDock.app")
        #expect(UpdateInstallLocation.resolve(bundleURL: writable) == .installable(writable))

        if case .installable = UpdateInstallLocation.resolve(bundleURL: readOnly.appendingPathComponent("CapacityDock.app")) {
            Issue.record("read-only folder should not be installable")
        }
        if case .installable = UpdateInstallLocation.resolve(bundleURL: fixture.root.appendingPathComponent("debug")) {
            Issue.record("a bare executable directory should not be installable")
        }
        if case .installable = UpdateInstallLocation.resolve(
            bundleURL: URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/y/d/CapacityDock.app")
        ) {
            Issue.record("translocated copies should not be installable")
        }
    }
}

private struct Fixture {
    let root: URL
    let work: URL
    let zip: URL
    let checksums: String

    init(version: String) throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory
            .appendingPathComponent("UpdateInstallerTests-\(UUID().uuidString)", isDirectory: true)
        work = root.appendingPathComponent("work", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        let app = source.appendingPathComponent("CapacityDock.app", isDirectory: true)
        try Self.makeApp(at: app, version: version)

        zip = root.appendingPathComponent("CapacityDock-\(version).zip")
        try UpdateInstallSteps.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path])
        checksums = "\(try UpdateChecksums.sha256(of: zip))  \(zip.lastPathComponent)\n"
    }

    static func makeApp(at app: URL, version: String) throws {
        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: macOS.appendingPathComponent("CapacityDock"))
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.dmao233.capacity-dock",
            "CFBundleShortVersionString": version
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }
}
