import AppKit
import FloatDockCore
import QuartzCore
import SwiftUI

/// Real inputs update these native layers at sample cadence; Core Animation
/// composites the ongoing decorative motion without a SwiftUI frame loop.
struct CurrentMetricGlyph: NSViewRepresentable {
    let kind: MetricKind
    let value: Double?
    let network: NetworkValue?
    let accent: Color
    let secondary: Color
    let animated: Bool

    func makeNSView(context: Context) -> CurrentGlyphNativeView {
        let view = CurrentGlyphNativeView(kind: kind)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: CurrentGlyphNativeView, context: Context) {
        view.configure(value: value, network: network, accent: accent, secondary: secondary, animated: animated)
    }

    static func dismantleNSView(_ view: CurrentGlyphNativeView, coordinator: ()) {
        view.stopAnimations()
    }
}

@MainActor
final class CurrentGlyphNativeView: NSView {
    private let kind: MetricKind
    private let surface = CALayer()
    private lazy var waveBack = CAShapeLayer()
    private lazy var waveFront = CAShapeLayer()
    private lazy var slabs = (0..<3).map { _ in CAShapeLayer() }
    private lazy var matrix = CALayer()
    private lazy var cells = (0..<12).map { _ in CAShapeLayer() }
    private lazy var highlights = (0..<12).map { _ in CAShapeLayer() }
    private lazy var lanes = (0..<2).map { _ in CALayer() }
    private lazy var tracks = (0..<2).map { _ in CAShapeLayer() }
    private lazy var packets = (0..<2).map { _ in CAGradientLayer() }

    private var percent: Double?
    private var received: Double?
    private var sent: Double?
    private var requestedAnimation = false
    private var accentInput: Color?
    private var secondaryInput: Color?
    private var resolvedAccent = NSColor.clear
    private var resolvedSecondary = NSColor.clear
    private var layoutBounds = CGRect.null
    private var currentScale: CGFloat = 0
    private var litCellCount = -1
    private var memoryScale: CGFloat = 1

    init(kind: MetricKind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.addSublayer(surface)
        surface.isGeometryFlipped = true
        surface.isOpaque = false
        setAccessibilityElement(false)
        makeLayers()
    }

    required init?(coder: NSCoder) { return nil }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(value: Double?, network: NetworkValue?, accent: Color, secondary: Color, animated: Bool) {
        let nextPercent = value.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
        let nextReceived = validRate(network?.receiveBytesPerSecond)
        let nextSent = validRate(network?.sendBytesPerSecond)
        let valueChanged = percent != nextPercent
        let availabilityChanged = (percent == nil) != (nextPercent == nil)
        let trafficChanged = received != nextReceived || sent != nextSent
        let colorsChanged = accentInput != accent || secondaryInput != secondary
        percent = nextPercent
        received = nextReceived
        sent = nextSent
        requestedAnimation = animated
        accentInput = accent
        secondaryInput = secondary

        withoutImplicitAnimations {
            if colorsChanged { resolveColors() }
            if colorsChanged || availabilityChanged { updateColors() }
            if kind == .cpu, valueChanged { updateWavePath() }
            if kind == .gpu, valueChanged || colorsChanged { updateCells() }
            if kind == .network, trafficChanged || colorsChanged { updatePacketVisibility() }
        }
        updateAnimationState()
    }

    override func layout() {
        super.layout()
        guard bounds != layoutBounds else { return }
        layoutBounds = bounds
        withoutImplicitAnimations {
            surface.frame = bounds
            switch kind {
            case .cpu:
                waveBack.frame = surface.bounds
                waveFront.frame = surface.bounds
                waveBack.transform = CATransform3DMakeTranslation(0, 3, 0)
                updateWavePath()
            case .memory:
                // Include the stacked offsets and breathing travel in the fit,
                // so projected slabs never cross the adjacent text labels.
                memoryScale = min(1, bounds.height / 49, bounds.width / 42)
                for (index, slab) in slabs.enumerated() {
                    slab.bounds = CGRect(x: 0, y: 0, width: 36, height: 24)
                    slab.position = CGPoint(x: bounds.width / 2, y: bounds.height / 2 + (CGFloat(1 - index) * 6 + 1.5) * memoryScale)
                    slab.path = CGPath(roundedRect: slab.bounds, cornerWidth: 7, cornerHeight: 7, transform: nil)
                    slab.transform = CATransform3DConcat(
                        CATransform3DMakeRotation(48 * .pi / 180, 1, 0, 0),
                        CATransform3DMakeRotation(-32 * .pi / 180, 0, 0, 1)
                    )
                    slab.transform = CATransform3DScale(slab.transform, memoryScale, memoryScale, memoryScale)
                }
            case .gpu:
                matrix.bounds = CGRect(x: 0, y: 0, width: 40, height: 29)
                matrix.position = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
                matrix.transform = CATransform3DMakeRotation(-12 * .pi / 180, 0, 0, 1)
                let matrixScale = min(1, bounds.height / 37, bounds.width / 46)
                matrix.transform = CATransform3DScale(matrix.transform, matrixScale, matrixScale, 1)
                for index in cells.indices {
                    cells[index].frame = CGRect(x: CGFloat(index % 4) * 11, y: CGFloat(index / 4) * 11, width: 7, height: 7)
                    cells[index].path = CGPath(roundedRect: cells[index].bounds, cornerWidth: 2, cornerHeight: 2, transform: nil)
                    highlights[index].frame = cells[index].frame
                    highlights[index].path = CGPath(roundedRect: CGRect(x: 1, y: 0, width: 5, height: 0.6), cornerWidth: 0.3, cornerHeight: 0.3, transform: nil)
                }
            case .network:
                let startY = (bounds.height - 16) / 2
                for index in lanes.indices {
                    lanes[index].frame = CGRect(x: (bounds.width - 48) / 2, y: startY + CGFloat(index) * 12, width: 48, height: 4)
                    tracks[index].frame = lanes[index].bounds
                    tracks[index].path = CGPath(roundedRect: CGRect(x: 0, y: 1.5, width: 48, height: 1), cornerWidth: 0.5, cornerHeight: 0.5, transform: nil)
                    packets[index].bounds = CGRect(x: 0, y: 0, width: 12, height: 3)
                    packets[index].position = CGPoint(x: 24, y: 2)
                }
            }
            updateBackingScale()
        }
        // Position animation endpoints change only when actual bounds change.
        if kind == .memory {
            for slab in slabs { slab.removeAnimation(forKey: "current.memory.breathe") }
        }
        updateAnimationState()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        withoutImplicitAnimations { updateBackingScale() }
        if window == nil { stopAnimations() }
        else { updateAnimationState() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        withoutImplicitAnimations { updateBackingScale() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        withoutImplicitAnimations {
            resolveColors()
            updateColors()
        }
    }

    func stopAnimations() {
        switch kind {
        case .cpu: waveFront.removeAllAnimations()
        case .memory: for slab in slabs { slab.removeAllAnimations() }
        case .gpu: matrix.removeAllAnimations()
        case .network: for packet in packets { packet.removeAllAnimations() }
        }
    }

    private func makeLayers() {
        withoutImplicitAnimations {
            switch kind {
            case .cpu:
                for wave in [waveBack, waveFront] {
                    wave.fillColor = nil
                    wave.lineCap = .round
                    wave.lineJoin = .round
                    surface.addSublayer(wave)
                }
                waveBack.lineWidth = 1.1
                waveFront.lineWidth = 1.7
            case .memory:
                for (index, slab) in slabs.enumerated() {
                    slab.lineWidth = 0.7
                    slab.opacity = Float(0.38 + Double(index) * 0.25)
                    surface.addSublayer(slab)
                }
            case .gpu:
                surface.addSublayer(matrix)
                for index in cells.indices {
                    matrix.addSublayer(cells[index])
                    matrix.addSublayer(highlights[index])
                }
            case .network:
                for index in lanes.indices {
                    surface.addSublayer(lanes[index])
                    lanes[index].masksToBounds = true
                    lanes[index].addSublayer(tracks[index])
                    lanes[index].addSublayer(packets[index])
                    packets[index].cornerRadius = 1.5
                    packets[index].startPoint = CGPoint(x: index == 0 ? 0 : 1, y: 0.5)
                    packets[index].endPoint = CGPoint(x: index == 0 ? 1 : 0, y: 0.5)
                }
            }
        }
    }

    private func resolveColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if let accentInput {
                let native = NSColor(accentInput)
                resolvedAccent = native.usingColorSpace(.sRGB) ?? native
            }
            if let secondaryInput {
                let native = NSColor(secondaryInput)
                resolvedSecondary = native.usingColorSpace(.sRGB) ?? native
            }
        }
    }

    private func updateColors() {
        switch kind {
        case .cpu:
            waveBack.strokeColor = resolvedAccent.withAlphaComponent(0.20).cgColor
            waveFront.strokeColor = resolvedAccent.withAlphaComponent(percent == nil ? 0.28 : 0.85).cgColor
        case .memory:
            let fill = (NSColor.white.blended(withFraction: 0.45, of: resolvedAccent) ?? resolvedAccent)
                .withAlphaComponent(percent == nil ? 0.10 : 0.18).cgColor
            let stroke = resolvedAccent.withAlphaComponent(percent == nil ? 0.18 : 0.45).cgColor
            for slab in slabs {
                slab.fillColor = fill
                slab.strokeColor = stroke
            }
        case .gpu:
            litCellCount = -1
            updateCells()
            for highlight in highlights { highlight.fillColor = NSColor.white.withAlphaComponent(0.22).cgColor }
        case .network:
            for index in lanes.indices {
                let color = index == 0 ? resolvedAccent : resolvedSecondary
                tracks[index].fillColor = color.withAlphaComponent(0.20).cgColor
                packets[index].colors = [color.withAlphaComponent(0.12).cgColor, color.withAlphaComponent(0.85).cgColor]
            }
            updatePacketVisibility()
        }
    }

    private func updateCells() {
        let count = Int(ceil((percent ?? 0) / 100 * 12))
        guard count != litCellCount else { return }
        litCellCount = count
        let active = resolvedAccent.withAlphaComponent(0.88).cgColor
        let resting = resolvedAccent.withAlphaComponent(0.15).cgColor
        for (index, cell) in cells.enumerated() { cell.fillColor = index < count ? active : resting }
    }

    private func updatePacketVisibility() {
        packets[0].opacity = (received ?? 0) > 0 ? 1 : 0
        packets[1].opacity = (sent ?? 0) > 0 ? 1 : 0
    }

    private func updateWavePath() {
        guard surface.bounds.width > 0, surface.bounds.height > 0 else { return }
        let energy = (percent ?? 0) == 0 ? 0 : 0.42 + (percent ?? 0) / 100 * 0.58
        let rect = surface.bounds
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: CGFloat(x / 64) * rect.width, y: rect.midY + CGFloat((y - 16) / 32 * energy) * rect.height)
        }
        let path = CGMutablePath()
        path.move(to: point(0, 17))
        path.addCurve(to: point(9, 15), control1: point(5, 17), control2: point(5, 15))
        path.addCurve(to: point(16, 22), control1: point(13, 15), control2: point(13, 22))
        path.addCurve(to: point(23, 5), control1: point(19, 22), control2: point(19, 5))
        path.addCurve(to: point(31, 28), control1: point(27, 5), control2: point(27, 28))
        path.addCurve(to: point(39, 8), control1: point(35, 28), control2: point(35, 8))
        path.addCurve(to: point(48, 19), control1: point(44, 8), control2: point(44, 19))
        path.addCurve(to: point(57, 15), control1: point(53, 19), control2: point(53, 15))
        path.addCurve(to: point(64, 16), control1: point(61, 15), control2: point(61, 16))
        waveFront.path = path
        waveBack.path = path
    }

    private func updateAnimationState() {
        let allowed = requestedAnimation && window != nil && window?.isVisible == true
        switch kind {
        case .cpu:
            setAnimation(on: waveFront, key: "current.cpu.breathe", enabled: allowed && (percent ?? 0) > 0) {
                pulse(keyPath: "transform.scale.y", from: 0.86, to: 1.06)
            }
        case .memory:
            for (index, slab) in slabs.enumerated() where index > 0 {
                setAnimation(on: slab, key: "current.memory.breathe", enabled: allowed && (percent ?? 0) > 0) {
                    pulse(keyPath: "position.y", from: slab.position.y, to: slab.position.y - CGFloat(index) * 1.5 * memoryScale)
                }
            }
        case .gpu:
            setAnimation(on: matrix, key: "current.gpu.breathe", enabled: allowed && (percent ?? 0) > 0) {
                pulse(keyPath: "opacity", from: 0.66, to: 1.0)
            }
        case .network:
            for index in packets.indices {
                let rate = index == 0 ? received : sent
                setAnimation(on: packets[index], key: "current.network.travel", enabled: allowed && (rate ?? 0) > 0) {
                    let animation = CABasicAnimation(keyPath: "transform.translation.x")
                    animation.fromValue = index == 0 ? -30 : 30
                    animation.toValue = index == 0 ? 30 : -30
                    animation.duration = index == 0 ? 2.3 : 2.7
                    animation.repeatCount = .infinity
                    animation.timingFunction = CAMediaTimingFunction(name: .linear)
                    return animation
                }
            }
        }
    }

    private func pulse(keyPath: String, from: Any, to: Any) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = 1.8
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }

    private func setAnimation(on layer: CALayer, key: String, enabled: Bool, make: () -> CAAnimation) {
        if enabled {
            if layer.animation(forKey: key) == nil { layer.add(make(), forKey: key) }
        } else if layer.animation(forKey: key) != nil {
            layer.removeAnimation(forKey: key)
        }
    }

    private func updateBackingScale() {
        let scale = window?.backingScaleFactor ?? 2
        guard scale != currentScale else { return }
        currentScale = scale
        for layer in allLayers { layer.contentsScale = scale }
    }

    private var allLayers: [CALayer] {
        var result = [surface]
        switch kind {
        case .cpu:
            result.append(contentsOf: [waveBack, waveFront])
        case .memory:
            result.append(contentsOf: slabs)
        case .gpu:
            result.append(matrix)
            result.append(contentsOf: cells)
            result.append(contentsOf: highlights)
        case .network:
            result.append(contentsOf: lanes)
            result.append(contentsOf: tracks)
            result.append(contentsOf: packets)
        }
        return result
    }

    private func validRate(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }

    private func withoutImplicitAnimations(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}
