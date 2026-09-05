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
}
