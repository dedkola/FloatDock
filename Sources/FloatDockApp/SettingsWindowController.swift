import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(appearance: AppearanceSettings) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 790, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FloatDock Settings"
        window.identifier = NSUserInterfaceItemIdentifier("FloatDockSettings")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 710, height: 570)
        let hosting = NSHostingController(rootView: SettingsView(appearance: appearance))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 790, height: 740))
        if let screen = window.screen ?? NSScreen.main {
            var frame = window.frame
            frame.size.width = min(frame.width, screen.visibleFrame.width)
            frame.size.height = min(frame.height, screen.visibleFrame.height)
            window.setFrame(frame, display: false)
        }
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { return nil }

    func show() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func shutdown() {
        close()
    }
}
