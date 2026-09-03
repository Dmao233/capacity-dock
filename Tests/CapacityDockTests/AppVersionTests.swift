import Foundation
import Testing
@testable import CapacityDock

@Suite("App version")
struct AppVersionTests {
    @Test("leading v is stripped")
    func stripsVPrefix() {
        #expect(AppVersion.normalize("v0.1.2") == "0.1.2")
        #expect(AppVersion.normalize("0.1.2") == "0.1.2")
    }

    @Test("newer dotted versions compare numerically")
    func comparesDottedVersions() {
        #expect(AppVersion.isNewer("0.1.2", than: "0.1.1"))
        #expect(AppVersion.isNewer("v0.2.0", than: "0.1.9"))
        #expect(!AppVersion.isNewer("0.1.1", than: "0.1.1"))
        #expect(!AppVersion.isNewer("0.1.0", than: "0.1.1"))
        #expect(AppVersion.isNewer("1.0.0", than: "0.9.9"))
    }

    @Test("GitHub release JSON maps tag and zip asset")
    func decodesGitHubRelease() throws {
        let json = """
        {
          "tag_name": "v0.1.2",
          "html_url": "https://github.com/Dmao233/capacity-dock/releases/tag/v0.1.2",
          "assets": [
            {
              "name": "CapacityDock-0.1.2.zip",
              "browser_download_url": "https://github.com/Dmao233/capacity-dock/releases/download/v0.1.2/CapacityDock-0.1.2.zip"
            }
          ]
        }
        """.data(using: .utf8)!
        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        #expect(release.version == "0.1.2")
        #expect(release.zipAsset?.name == "CapacityDock-0.1.2.zip")
        #expect(AppVersion.isNewer(release.version, than: "0.1.1"))
    }
}
