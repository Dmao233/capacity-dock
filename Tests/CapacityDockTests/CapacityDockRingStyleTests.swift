import Foundation
import SwiftUI
import Testing
@testable import CapacityDock

@Suite("Ring style")
struct CapacityDockRingStyleTests {
    private func freshDefaults() -> UserDefaults {
        let name = "ring-style-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Hex colours round-trip and reject malformed input")
    func hexRoundTrip() {
        let rgb = CapacityDockRGB(hex: "#30D158")
        #expect(rgb?.hex == "#30D158")
        #expect(CapacityDockRGB(hex: "30d158")?.hex == "#30D158")
        #expect(CapacityDockRGB(hex: "#12345") == nil)
        #expect(CapacityDockRGB(hex: "zzzzzz") == nil)
    }

    @Test("Defaults: status mode, 5h ring shown, no custom colours")
    func defaults() {
        let style = CapacityDockPreferences.loadRingStyle(defaults: freshDefaults())
        #expect(style == .standard)
        #expect(style.mode == .status)
        #expect(style.showsSessionRing)
    }

    @Test("Custom colours, mode and 5h toggle persist; reset clears colours only")
    func persistence() {
        let defaults = freshDefaults()
        let pink = CapacityDockRGB(hex: "#FF2D55")!
        CapacityDockPreferences.setRingColor(pink, for: .session, defaults: defaults)
        CapacityDockPreferences.setRingColorMode(.fixed, defaults: defaults)
        CapacityDockPreferences.setShowsSessionRing(false, defaults: defaults)

        var style = CapacityDockPreferences.loadRingStyle(defaults: defaults)
        #expect(style.custom[.session] == pink)
        #expect(style.mode == .fixed)
        #expect(!style.showsSessionRing)

        CapacityDockPreferences.resetRingColors(defaults: defaults)
        style = CapacityDockPreferences.loadRingStyle(defaults: defaults)
        #expect(style.custom.isEmpty)
        #expect(style.mode == .fixed)
    }

    @Test("Per-ring colours still switch to the danger colour near exhaustion")
    func fixedModeDangerOverride() {
        var style = CapacityDockRingStyle()
        style.mode = .fixed
        let blue = CapacityDockRGB(hex: "#0A84FF")!
        let red = CapacityDockRGB(hex: "#FF0000")!
        style.custom[.session] = blue
        style.custom[.danger] = red
        #expect(style.color(for: 0.6, ring: .session) == blue.color)
        #expect(style.color(for: 0.95, ring: .session) == red.color)

        style.mode = .status
        #expect(style.color(for: 0.6, ring: .session) == style.color(.warning))
    }
}
