import AppKit
import FloatDockCore
import Foundation

@main
enum FloatDockEntry {
    @MainActor static func main() async {
        if CommandLine.arguments.contains("--probe") {
            await runProbe()
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }

    private static func runProbe() async {
        let args = CommandLine.arguments
        let index = args.firstIndex(of: "--probe") ?? 0
        let count = index + 1 < args.count ? Int(args[index + 1]) ?? 4 : 4
        let sampler = MetricsSampler()
        for iteration in 0..<max(1, min(count, 60)) {
            let snapshot = await sampler.readOnce()
            let data: [String: Any] = [
                "sample": iteration, "time": snapshot.timestamp.description,
                "cpu": snapshot.cpu.value.map { ["busyPercent": $0.busyPercent, "userPercent": $0.userPercent, "systemPercent": $0.systemPercent] } ?? ["status": String(describing: snapshot.cpu)],
                "memory": snapshot.memory.value.map { ["usedBytes": $0.usedBytes, "totalBytes": $0.totalBytes, "compressedBytes": $0.compressedBytes] } ?? ["status": String(describing: snapshot.memory)],
                "gpu": snapshot.gpu.value.map { ["name": $0.name, "utilizationPercent": $0.utilizationPercent] } ?? ["status": String(describing: snapshot.gpu)],
                "network": snapshot.network.value.map { ["interface": $0.interfaceName, "label": $0.interfaceLabel, "receiveBytesPerSecond": $0.receiveBytesPerSecond, "sendBytesPerSecond": $0.sendBytesPerSecond] } ?? ["status": String(describing: snapshot.network)]
            ]
            if let encoded = try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]), let text = String(data: encoded, encoding: .utf8) { print(text) }
            if iteration < count - 1 { try? await Task.sleep(for: .seconds(1)) }
        }
        await sampler.stop()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = MetricsStore()
    private let sampler = MetricsSampler()
    private let appearance = AppearanceSettings()
    private var dock: DockWindowController!
    private var settings: SettingsWindowController?
    private var statusItem: NSStatusItem!
    private var showItem: NSMenuItem!
    private var applicationShowItem: NSMenuItem!
    private var sampleTask: Task<Void, Never>?
    private var lifecycleTask: Task<Void, Never>?
    private var samplingRevision: UInt64 = 0
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var sleeping = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        dock = DockWindowController(store: store, appearance: appearance)
        appearance.onDesignChanged = { [weak self] design in self?.dock.applyDesign(design) }
        appearance.onMaterialChanged = { [weak self] in self?.dock.applyMaterial() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "rectangle.split.1x2", accessibilityDescription: "FloatDock") {
            image.isTemplate = true
            statusItem.button?.image = image
        }
        statusItem.button?.toolTip = "FloatDock"
        let menu = NSMenu()
        showItem = NSMenuItem(title: "Hide Dock", action: #selector(toggleDock), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        let focusItem = NSMenuItem(title: "Focus Dock", action: #selector(focusDock), keyEquivalent: "")
        focusItem.target = self
        menu.addItem(focusItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit FloatDock", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        let applicationMenu = NSMenu()
        let applicationItem = NSMenuItem(title: "FloatDock", action: nil, keyEquivalent: "")
        let applicationSubmenu = NSMenu(title: "FloatDock")
        let applicationSettings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        applicationSettings.target = self
        applicationSubmenu.addItem(applicationSettings)
        applicationSubmenu.addItem(.separator())
        applicationShowItem = NSMenuItem(title: "Hide Dock", action: #selector(toggleDock), keyEquivalent: "")
        applicationShowItem.target = self
        applicationSubmenu.addItem(applicationShowItem)
        let applicationFocus = NSMenuItem(title: "Focus Dock", action: #selector(focusDock), keyEquivalent: "")
        applicationFocus.target = self
        applicationSubmenu.addItem(applicationFocus)
        applicationSubmenu.addItem(.separator())
        let applicationQuit = NSMenuItem(title: "Quit FloatDock", action: #selector(quit), keyEquivalent: "q")
        applicationQuit.target = self
        applicationSubmenu.addItem(applicationQuit)
        applicationItem.submenu = applicationSubmenu
        applicationMenu.addItem(applicationItem)
        NSApp.mainMenu = applicationMenu
        observeLifecycle()
        dock.show()
        startSampling()
    }

    private func startSampling() {
        reconcileSampling()
    }

    private func pauseSampling() {
        reconcileSampling()
    }

    private func reconcileSampling() {
        store.animationsActive = !sleeping && dock.isVisible
        samplingRevision &+= 1
        let revision = samplingRevision
        sampleTask?.cancel()
        sampleTask = nil
        store.interruptHistory()
        let previous = lifecycleTask
        lifecycleTask = Task { [weak self, sampler] in
            await previous?.value
            await sampler.pause()
            guard let self, self.samplingRevision == revision, !self.sleeping, self.dock.isVisible else { return }
            let stream = await sampler.start()
            guard self.samplingRevision == revision else { await sampler.pause(); return }
            self.sampleTask = Task { [weak self] in
                for await snapshot in stream {
                    guard !Task.isCancelled, let self, self.samplingRevision == revision else { break }
                    self.store.update(snapshot)
                }
                if let self, self.samplingRevision == revision { self.sampleTask = nil }
            }
        }
    }

    @objc private func toggleDock() {
        if dock.isVisible { dock.hide(); pauseSampling() }
        else { dock.show(); startSampling() }
        updateVisibilityMenu()
    }
    @objc private func focusDock() {
        let wasVisible = dock.isVisible
        dock.focus()
        updateVisibilityMenu()
        if !wasVisible { startSampling() }
    }
    private func updateVisibilityMenu() {
        let title = dock.isVisible ? "Hide Dock" : "Show Dock"
        showItem.title = title
        applicationShowItem.title = title
    }
    @objc private func showSettings() {
        dock.closeDetails()
        if settings == nil { settings = SettingsWindowController(appearance: appearance) }
        settings?.show()
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private func observeLifecycle() {
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification) { [weak self] in self?.sleep() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.sleep() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) { [weak self] in self?.wake() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification) { [weak self] in self?.wake() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in self?.dock.closeDetails() }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in self?.dock.closeDetails(); self?.dock.place() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { [weak self] in self?.dock.applyMaterial() }
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping @MainActor () -> Void) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated { action() } }
        observers.append((center, observer))
    }
    private func sleep() { sleeping = true; dock.closeDetails(); pauseSampling() }
    private func wake() { sleeping = false; dock.place(); startSampling() }

    func applicationWillTerminate(_ notification: Notification) {
        samplingRevision &+= 1
        sampleTask?.cancel()
        lifecycleTask?.cancel()
        dock.shutdown()
        settings?.shutdown()
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        NSStatusBar.system.removeStatusItem(statusItem)
        Task { await sampler.stop() }
    }
}
