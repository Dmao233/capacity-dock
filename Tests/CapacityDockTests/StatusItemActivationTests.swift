import AppKit
import Testing
@testable import CapacityDock

@Suite("Status item activation")
struct StatusItemActivationTests {
    @Test("left click opens the itemized bill")
    func leftClickOpensBill() {
        #expect(StatusItemActivation.route(eventType: .leftMouseUp) == .openUsageDetails)
        #expect(StatusItemActivation.route(eventType: .leftMouseDown) == .openUsageDetails)
    }

    @Test("right click and control-click keep the settings menu")
    func rightClickShowsSettingsMenu() {
        #expect(StatusItemActivation.route(eventType: .rightMouseUp) == .showSettingsMenu)
        #expect(StatusItemActivation.route(eventType: .rightMouseDown) == .showSettingsMenu)
        #expect(StatusItemActivation.route(eventType: .leftMouseUp, modifierFlags: .control) == .showSettingsMenu)
    }
    @Test("Settings placement centers on the invoked display and keeps its top visible")
    func settingsPlacement() {
        let screen = CGRect(x: -1440, y: 25, width: 1440, height: 875)
        let size = CGSize(width: 880, height: 620)
        let origin = SettingsWindowPlacement.origin(size: size, visibleFrame: screen)
        let frame = CGRect(origin: origin, size: size)
        #expect(frame.midX == screen.midX)
        #expect(frame.midY == screen.midY)
        #expect(screen.contains(frame))
        let small = CGRect(x: 1920, y: 40, width: 800, height: 500)
        let overflow = SettingsWindowPlacement.origin(size: size, visibleFrame: small)
        #expect(overflow.x == small.minX)
        #expect(overflow.y + size.height == small.maxY)
    }
}
