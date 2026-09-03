import Foundation

struct GitHubRelease: Decodable, Equatable, Sendable {
    var tagName: String
    var htmlURL: String
    var assets: [Asset]

    struct Asset: Decodable, Equatable, Sendable {
        var name: String
        var browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }

    var version: String { AppVersion.normalize(tagName) }

    var zipAsset: Asset? {
        assets.first { $0.name.hasSuffix(".zip") && $0.name.hasPrefix("CapacityDock-") }
            ?? assets.first { $0.name.hasSuffix(".zip") }
    }
}

enum UpdateCheckResult: Equatable, Sendable {
    case upToDate(current: String, latest: String)
    case available(GitHubRelease)
    case failed(String)
}

enum UpdateChecker {
    static let releasesURL = URL(
        string: "https://api.github.com/repos/Dmao233/capacity-dock/releases/latest"
    )!

    static func check(
        currentVersion: String = AppVersion.current,
        session: URLSession = .shared
    ) async -> UpdateCheckResult {
        var request = URLRequest(url: releasesURL)
        request.setValue(
            "CapacityDock/\(currentVersion) (+https://github.com/Dmao233/capacity-dock)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return .failed("GitHub returned \(http.statusCode).")
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            if AppVersion.isNewer(release.version, than: currentVersion) {
                return .available(release)
            }
            return .upToDate(current: currentVersion, latest: release.version)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
