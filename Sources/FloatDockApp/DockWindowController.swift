import AppKit
import FloatDockCore
import SwiftUI

@MainActor
final class DockWindowController: NSObject, NSPopoverDelegate {
    let panel: DockPanel
    private let store: MetricsStore
    private let appearance: AppearanceSettings
    private let popover = NSPopover()
    private var anchors: [MetricKind: WeakView] = [:]
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var clickedSelection: MetricKind?
    private var restoreFocusOnClose = false
    private var closingFocusTarget: MetricKind?
    private var accessibleTiles: [MetricAccessibilityElement] = []
    private var dockSurface: DockSurfaceView!
    private var hosting: FirstMouseHostingView<DockView>!

    init(store: MetricsStore, appearance: AppearanceSettings) {
        self.store = store
        self.appearance = appearance
        let layout = appearance.design.layout
        panel = DockPanel(contentRect: NSRect(origin: .zero, size: layout.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = "FloatDock"
        panel.identifier = NSUserInterfaceItemIdentifier("FloatDockDock")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false

        let view = DockView(store: store, appearance: appearance, select: { [weak self] kind in self?.toggle(kind) }, registerAnchor: { [weak self] kind, view in self?.anchors[kind] = WeakView(view) })
        let hosting = FirstMouseHostingView(rootView: view)
        self.hosting = hosting
        hosting.frame = NSRect(origin: .zero, size: layout.size)
        hosting.autoresizingMask = [.width, .height]
        let surface = DockSurfaceView(frame: hosting.frame, cornerRadius: layout.cornerRadius, foreground: hosting)
        dockSurface = surface
        // Explicit children preserve the four-button contract at every material
        // strength, including when the decorative glass is completely hidden.
        accessibleTiles = MetricKind.allCases.map { kind in
            MetricAccessibilityElement(kind: kind, store: store, parent: surface,
                anchor: { [weak self] in self?.anchors[kind]?.value },
                action: { [weak self] in self?.clickedSelection = nil; self?.toggle(kind) })
        }
        surface.setAccessibilityChildren(accessibleTiles)
        panel.contentView = surface
        applyMaterial()

        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self

        // Preserve selection before AppKit's transient-dismissal processing so a
        // second click on the originating tile closes rather than reopens it.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            self.clickedSelection = nil
            if event.window === self.panel, let selected = self.store.selected,
               let anchor = self.anchors[selected]?.value,
               anchor.convert(anchor.bounds, to: nil).contains(event.locationInWindow) {
                self.clickedSelection = selected
            }
            return event
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let inDock = event.window === self.panel
            let inPopover = self.popover.contentViewController?.view.window === event.window
            if inDock { self.clickedSelection = nil }
            if event.keyCode == 53, inDock || inPopover || self.popover.isShown {
                self.closeDetails(restoreFocus: true)
                return nil
            }
            return event
        }
    }

    var isVisible: Bool { panel.isVisible }
    var detailsVisible: Bool { popover.isShown }

    func show() {
        place()
        panel.orderFrontRegardless()
    }

    func hide() {
        closeDetails()
        panel.orderOut(nil)
    }

    func focus() {
        show()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        store.focusTarget = .cpu
        store.focusRequest += 1
    }

    func place() {
        guard let screen = Self.primaryScreen else { return }
        let frame = screen.visibleFrame
        let size = appearance.design.layout.size
        let origin = CGPoint(x: frame.maxX - size.width - 12, y: frame.midY - size.height / 2)
        panel.setFrameOrigin(origin)
    }

    func applyDesign(_ design: DockDesign) {
        closeDetails()
        clickedSelection = nil
        let layout = design.layout
        panel.setContentSize(layout.size)
        dockSurface.frame = NSRect(origin: .zero, size: layout.size)
        dockSurface.cornerRadius = layout.cornerRadius
        hosting.frame = NSRect(origin: .zero, size: layout.size)
        place()
        // Existing representables re-register their actual AppKit frames as the
        // layout updates. Keep those anchors rather than guessing new positions.
    }

    func applyMaterial() {
        dockSurface.applyMaterial(transparency: appearance.transparency, glassStrength: appearance.glassStrength)
    }

    private static var primaryScreen: NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return number.uint32Value == CGMainDisplayID()
        } ?? NSScreen.screens.first
    }

    private func toggle(_ kind: MetricKind) {
        let wasSelected = clickedSelection == kind || (popover.isShown && store.selected == kind)
        clickedSelection = nil
        if wasSelected { closeDetails(); return }
        showDetails(kind)
    }

    func showDetails(_ kind: MetricKind) {
        guard let anchor = anchors[kind]?.value, anchor.window != nil else { return }
        store.selected = kind
        let root = MetricDetailView(kind: kind, store: store, close: { [weak self] in self?.closeDetails(restoreFocus: true) })
        let controller = NSHostingController(rootView: root)
        controller.sizingOptions = [.preferredContentSize, .intrinsicContentSize]
        popover.contentViewController = controller
        popover.contentSize = controller.view.fittingSize
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minX)
        // Keep the transient content reachable from the explicit dock AX tree.
        controller.view.setAccessibilityElement(true)
        controller.view.setAccessibilityRole(.popover)
        controller.view.setAccessibilityLabel("\(kind.title) details")
        dockSurface.setAccessibilityChildren(accessibleTiles + [controller.view])
    }

    func closeDetails(restoreFocus: Bool = false) {
        restoreFocusOnClose = restoreFocus
        if popover.isShown { popover.performClose(nil) }
        else { store.selected = nil }
    }

    func popoverDidClose(_ notification: Notification) {
        defer { closingFocusTarget = nil }
        guard !popover.isShown else { return }
        if let previous = closingFocusTarget, panel.isVisible {
            panel.makeKey()
            store.focusTarget = previous
            store.focusRequest += 1
        }
    }

    func popoverWillClose(_ notification: Notification) {
        closingFocusTarget = restoreFocusOnClose ? store.selected : nil
        store.selected = nil
        dockSurface.setAccessibilityChildren(accessibleTiles)
        restoreFocusOnClose = false
    }

    func shutdown() {
        closeDetails()
        panel.orderOut(nil)
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        mouseMonitor = nil
        keyMonitor = nil
    }

    func diagnosticState() -> [String: Any] {
        ["dockVisible": isVisible, "popoverVisible": detailsVisible, "selectedMetric": store.selected?.title ?? "none", "frame": NSStringFromRect(panel.frame), "material": "NSGlassEffectView.clear", "design": appearance.design.rawValue,
         "transparency": appearance.transparency, "glassStrength": appearance.glassStrength, "materialState": dockSurface.materialState]
    }
}

private final class WeakView {
    weak var value: NSView?
    init(_ value: NSView) { self.value = value }
}

final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class MetricAccessibilityElement: NSAccessibilityElement {
    @MainActor private final class State {
        let kind: MetricKind
        let store: MetricsStore
        weak var parentView: NSView?
        let anchor: @MainActor () -> NSView?
        let action: @MainActor () -> Void

        init(kind: MetricKind, store: MetricsStore, parent: NSView, anchor: @escaping @MainActor () -> NSView?, action: @escaping @MainActor () -> Void) {
            self.kind = kind
            self.store = store
            parentView = parent
            self.anchor = anchor
            self.action = action
        }
    }

    private let state: State

    @MainActor init(kind: MetricKind, store: MetricsStore, parent: NSView, anchor: @escaping @MainActor () -> NSView?, action: @escaping @MainActor () -> Void) {
        state = State(kind: kind, store: store, parent: parent, anchor: anchor, action: action)
        super.init()
        setAccessibilityRole(.button)
        setAccessibilityLabel(kind.title)
        setAccessibilityIdentifier("widget.\(kind.shortTitle.lowercased())")
        setAccessibilityEnabled(true)
    }

    // Objective-C accessibility overrides are nonisolated. Keep all UI state in
    // the main-actor holder and bridge synchronously, including callers outside
    // AppKit's UI event loop. The immutable holder is Sendable by actor isolation;
    // the accessibility element itself never needs unchecked Sendable conformance.
    private static func onMain<Value: Sendable>(_ body: @escaping @MainActor @Sendable () -> Value) -> Value {
        if Thread.isMainThread { return MainActor.assumeIsolated { body() } }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { body() } }
    }

    override func accessibilityParent() -> Any? {
        let state = state
        let parent: NSView? = Self.onMain { state.parentView }
        return parent
    }
    override func accessibilityValue() -> Any? {
        let state = state
        let value: String = Self.onMain { state.store.accessibilityValue(for: state.kind) }
        return value
    }
    override func accessibilityHelp() -> String? {
        let state = state
        return Self.onMain { state.store.selected == state.kind ? "Close details" : "Show details" }
    }
    override func accessibilityWindow() -> Any? {
        let state = state
        let window: NSWindow? = Self.onMain { state.anchor()?.window }
        return window
    }
    override func accessibilityTopLevelUIElement() -> Any? { accessibilityWindow() }
    override func accessibilityFrame() -> NSRect {
        let state = state
        return Self.onMain {
            guard let view = state.anchor(), let window = view.window else { return .zero }
            return window.convertToScreen(view.convert(view.bounds, to: nil))
        }
    }
    override func accessibilityPerformPress() -> Bool {
        let state = state
        return Self.onMain { state.action(); return true }
    }
}
