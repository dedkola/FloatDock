import AppKit
import QuartzCore

/// The material is behind the content so appearance controls never fade text,
/// interactive tiles, their accessibility elements, or the detail popovers.
@MainActor
final class DockSurfaceView: NSView {
    private let backing = CAShapeLayer()
    private let glass = BackgroundGlassView()
    private let foreground: NSView
    private var transparency = 1.0
    private var glassStrength = 1.0

    private let cornerRadius = DockLayout.nativeCornerRadius

    init(frame: NSRect, foreground: NSView) {
        self.foreground = foreground
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(backing)
        glass.style = .clear
        // Native glass's built-in radius has a longer continuous transition.
        // Clip rectangular glass to the reference Dock's fixed circular outline.
        glass.cornerRadius = 0
        glass.wantsLayer = true
        glass.layer?.cornerCurve = .circular
        glass.layer?.masksToBounds = true
        glass.setAccessibilityElement(false)
        let emptyContent = NSView(frame: bounds)
        emptyContent.setAccessibilityElement(false)
        glass.contentView = emptyContent
        glass.autoresizingMask = [.width, .height]
        foreground.autoresizingMask = [.width, .height]
        addSubview(glass)
        addSubview(foreground)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("System widgets")
        needsLayout = true
        applyMaterial(transparency: 1, glassStrength: 1)
    }

    required init?(coder: NSCoder) { return nil }
    override var isOpaque: Bool { false }

    func applyMaterial(transparency: Double, glassStrength: Double) {
        self.transparency = Self.normalized(transparency)
        self.glassStrength = Self.normalized(glassStrength)
        updateMaterial()
    }

    override func layout() {
        super.layout()
        withoutImplicitAnimations {
            backing.frame = bounds
            backing.path = outline
            glass.frame = bounds
            glass.layer?.cornerRadius = cornerRadius
            foreground.frame = bounds
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateMaterial()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        backing.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard outline.contains(local) else { return nil }
        return super.hitTest(point)
    }

    // The native reference joins the straight edges with a short circular arc.
    private var outline: CGPath {
        CGPath(roundedRect: bounds, cornerWidth: cornerRadius,
               cornerHeight: cornerRadius, transform: nil)
    }

    var materialState: [String: Double] {
        ["backingOpacity": Double(backing.opacity), "glassOpacity": Double(glass.alphaValue),
         "foregroundOpacity": Double(foreground.alphaValue)]
    }

    private func updateMaterial() {
        let reducedTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        withoutImplicitAnimations {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                backing.fillColor = NSColor.windowBackgroundColor.cgColor
            }
            backing.opacity = reducedTransparency ? 1 : Float(1 - transparency)
            backing.contentsScale = window?.backingScaleFactor ?? 2
            glass.alphaValue = reducedTransparency ? 0 : CGFloat(glassStrength)
            glass.isHidden = glass.alphaValue == 0
        }
    }

    private static func normalized(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 1
    }

    private func withoutImplicitAnimations(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}

private final class BackgroundGlassView: NSGlassEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
