import AppKit
import SwiftUI

/// How the dock rings and detail bars pick their colour.
enum CapacityDockRingColorMode: String, CaseIterable, Sendable {
    /// Colour follows how much of the limit is used (green → red).
    case status
    /// Each ring keeps its own colour, like Activity rings.
    case fixed

    var displayName: String {
        switch self {
        case .status: NSLocalizedString("By usage", comment: "")
        case .fixed: NSLocalizedString("Per ring", comment: "")
        }
    }
}

/// An sRGB colour persisted as `#RRGGBB`. A nil slot in the style means the
/// matching system colour, so untouched defaults keep following macOS.
struct CapacityDockRGB: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    init?(_ color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }

    var hex: String {
        func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
}

struct CapacityDockRingStyle: Equatable, Sendable {
    enum Slot: String, CaseIterable, Sendable {
        case normal, warning, critical, danger
        case weekly, session

        var defaultColor: Color {
            switch self {
            case .normal: .green
            case .warning: .yellow
            case .critical: .orange
            case .danger: .red
            case .weekly: .green
            case .session: .cyan
            }
        }

        var displayName: String {
            switch self {
            case .normal: NSLocalizedString("Under 50%", comment: "")
            case .warning: NSLocalizedString("50–75%", comment: "")
            case .critical: NSLocalizedString("75–90%", comment: "")
            case .danger: NSLocalizedString("90% and up", comment: "")
            case .weekly: NSLocalizedString("Weekly ring", comment: "")
            case .session: NSLocalizedString("5h ring", comment: "")
            }
        }

        static let statusSlots: [Slot] = [.normal, .warning, .critical, .danger]
        static let fixedSlots: [Slot] = [.weekly, .session]
    }

    enum Ring: Sendable {
        case weekly, session
    }

    var mode: CapacityDockRingColorMode = .status
    var showsSessionRing = true
    var custom: [Slot: CapacityDockRGB] = [:]

    static let standard = CapacityDockRingStyle()

    func color(_ slot: Slot) -> Color {
        custom[slot]?.color ?? slot.defaultColor
    }

    func statusColor(for percent: Double) -> Color {
        switch QuotaSummary.severity(for: percent) {
        case .normal: color(.normal)
        case .warning: color(.warning)
        case .critical: color(.critical)
        case .danger: color(.danger)
        }
    }

    /// Per-ring mode still turns the danger colour once a limit is nearly
    /// spent, so a fixed palette never hides an exhausted quota.
    func color(for percent: Double, ring: Ring) -> Color {
        switch mode {
        case .status:
            return statusColor(for: percent)
        case .fixed:
            if QuotaSummary.severity(for: percent) == .danger { return color(.danger) }
            return color(ring == .weekly ? .weekly : .session)
        }
    }
}
