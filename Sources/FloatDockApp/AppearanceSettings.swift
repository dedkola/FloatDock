import CoreGraphics
import CoreFoundation
import Foundation
import Observation

enum DockDesign: String, CaseIterable, Identifiable, Sendable {
    case current
    case float
    case orbit
    case ribbon

    var id: Self { self }

    var title: String {
        switch self {
        case .current: "Current"
        case .float: "Float"
        case .orbit: "Orbit"
        case .ribbon: "Ribbon"
        }
    }

    var subtitle: String {
        switch self {
        case .current: "Distinctive glyphs for each metric."
        case .float: "Glass cards with a quiet history trace."
        case .orbit: "Circular gauges with open activity arcs."
        case .ribbon: "A shorter dock with segmented meters."
        }
    }

    var layout: DockLayout {
        // Native hosting adds 5 pt at each edge. These insets halve the rendered
        // margins and gaps while the original outer dock dimensions stay fixed.
        switch self {
        case .current:
            DockLayout(size: CGSize(width: 98, height: 390), padding: 2, spacing: 4, tileRadius: 21)
        case .float:
            DockLayout(size: CGSize(width: 96, height: 390), padding: 2, spacing: 4, tileRadius: 21)
        case .orbit:
            DockLayout(size: CGSize(width: 94, height: 352), padding: 2.5, spacing: 6, tileRadius: 37)
        case .ribbon:
            DockLayout(size: CGSize(width: 112, height: 291), padding: 1.5, spacing: 2.5, tileRadius: 18)
        }
    }
}

struct DockLayout: Equatable, Sendable {
    let size: CGSize
    let padding: CGFloat
    let spacing: CGFloat
    let tileRadius: CGFloat

    /// The native Dock reference has a 31 px corner at 2x screenshot density.
    /// Keep its physical radius fixed, independent of the dock's width or design.
    static let nativeCornerRadius: CGFloat = 15.5
    var cornerRadius: CGFloat { Self.nativeCornerRadius }

    var tileSize: CGSize {
        CGSize(width: size.width - 2 * padding, height: (size.height - 3 * spacing - 2 * padding) / 4)
    }
}

@MainActor @Observable
final class AppearanceSettings {
    static let designPreferenceKey = "floatdock.appearance.design"
    static let transparencyPreferenceKey = "floatdock.appearance.transparency"
    static let glassStrengthPreferenceKey = "floatdock.appearance.glassStrength"

    var design: DockDesign {
        didSet {
            guard design != oldValue else { return }
            defaults.set(design.rawValue, forKey: Self.designPreferenceKey)
            onDesignChanged?(design)
        }
    }

    var transparency: Double {
        get { transparencyValue }
        set {
            let value = Self.normalizedMaterialValue(newValue)
            guard transparencyValue != value else { return }
            transparencyValue = value
            defaults.set(value, forKey: Self.transparencyPreferenceKey)
            onMaterialChanged?()
        }
    }

    var glassStrength: Double {
        get { glassStrengthValue }
        set {
            let value = Self.normalizedMaterialValue(newValue)
            guard glassStrengthValue != value else { return }
            glassStrengthValue = value
            defaults.set(value, forKey: Self.glassStrengthPreferenceKey)
            onMaterialChanged?()
        }
    }

    private var transparencyValue: Double
    private var glassStrengthValue: Double
    @ObservationIgnored var onDesignChanged: ((DockDesign) -> Void)?
    @ObservationIgnored var onMaterialChanged: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        design = defaults.string(forKey: Self.designPreferenceKey).flatMap(DockDesign.init(rawValue:)) ?? .current
        transparencyValue = Self.restoredMaterialValue(from: defaults, key: Self.transparencyPreferenceKey)
        glassStrengthValue = Self.restoredMaterialValue(from: defaults, key: Self.glassStrengthPreferenceKey)
    }

    /// Reset both material controls together without changing the selected design.
    func resetMaterialDefaults() {
        guard transparencyValue != 1 || glassStrengthValue != 1 else { return }
        transparencyValue = 1
        glassStrengthValue = 1
        defaults.set(1.0, forKey: Self.transparencyPreferenceKey)
        defaults.set(1.0, forKey: Self.glassStrengthPreferenceKey)
        onMaterialChanged?()
    }

    private static func normalizedMaterialValue(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(1, max(0, value))
    }

    private static func restoredMaterialValue(from defaults: UserDefaults, key: String) -> Double {
        guard let number = defaults.object(forKey: key) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return 1 }
        return normalizedMaterialValue(number.doubleValue)
    }
}
