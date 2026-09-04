import Foundation

enum AppVersion {
    /// Bump this with every GitHub release. Packaged builds also read
    /// CFBundleShortVersionString from Info.plist.
    static let marketing = "0.4.1"

    static var current: String {
        if let fromBundle = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String {
            let trimmed = fromBundle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != "1.0" {
                return trimmed
            }
        }
        return marketing
    }

    static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "v" || trimmed.first == "V" {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    /// Numeric dotted compare: `0.1.2` is newer than `0.1.1`.
    static func isNewer(_ latest: String, than current: String) -> Bool {
        let lhs = components(normalize(latest))
        let rhs = components(normalize(current))
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { part in
            Int(part.prefix { $0.isNumber }) ?? 0
        }
    }
}
