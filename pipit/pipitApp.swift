import SwiftUI
import AppKit

@main
struct pipitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No windows — menu bar only
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var sessionManager: SessionManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["hoverTransparencyEnabled": true])
        sessionManager = SessionManager()
        NSApp.setActivationPolicy(.accessory) // no dock icon

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "pip.fill", accessibilityDescription: "Pipit")
            button.action = #selector(togglePopover)
            button.target = self
        }
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        let hostingController = NSHostingController(
            rootView: ContentView(sessionManager: sessionManager)
                .frame(width: 340)
        )
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 340, height: 580)
        popover.contentViewController = hostingController
        popover.contentSize = NSSize(width: 340, height: 580)
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
