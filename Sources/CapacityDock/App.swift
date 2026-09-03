import AppKit
import SwiftUI

@main
struct CapacityDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            CapacityDockSettingsView(store: appDelegate.store)
                .frame(minWidth: 420, minHeight: 520)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = CapacityDockStore.demo()
    private var controller: CapacityDockController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        seedFirstLaunchIfNeeded()
        controller = CapacityDockController(store: store)
        controller?.start()
        installStatusItem()
        NotificationCenter.default.addObserver(
            forName: .capacityDockOpenProviderSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.openSettings()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func seedFirstLaunchIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: CapacityDockPreferences.selectedProvidersKey) == nil {
            CapacityDockPreferences.setSelectedProviders([.grok, .claude, .copilot, .codex])
            CapacityDockPreferences.setPreferredProvider(.grok)
        }
        if defaults.object(forKey: CapacityDockPreferences.enabledKey) == nil {
            CapacityDockPreferences.setEnabled(true)
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "◉"
        item.button?.toolTip = NSLocalizedString("Capacity Dock", comment: "")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: NSLocalizedString("Show Capacity Dock", comment: ""),
            action: #selector(showDock),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: NSLocalizedString("Capacity Dock Settings…", comment: ""),
            action: #selector(openSettings),
            keyEquivalent: ","
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: NSLocalizedString("Quit Capacity Dock", comment: ""),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        menu.items.forEach { $0.target = $0.action == #selector(NSApplication.terminate(_:)) ? nil : self }
        item.menu = menu
        statusItem = item
    }

    @objc func showDock() {
        CapacityDockPreferences.setEnabled(true)
    }

    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
