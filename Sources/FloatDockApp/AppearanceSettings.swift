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
        switch self {
        case .current:
            DockLayout(tileSize: CGSize(width: 80, height: 87), padding: 9, spacing: 8, cornerRadius: 29, tileRadius: 21)
        case .float:
            DockLayout(tileSize: CGSize(width: 78, height: 87), padding: 9, spacing: 8, cornerRadius: 29, tileRadius: 21)
        case .orbit:
            DockLayout(tileSize: CGSize(width: 74, height: 74), padding: 10, spacing: 12, cornerRadius: 45, tileRadius: 37)
        case .ribbon:
            DockLayout(tileSize: CGSize(width: 96, height: 65), padding: 8, spacing: 5, cornerRadius: 26, tileRadius: 18)
        }
    }
}

struct DockLayout: Equatable, Sendable {
    let tileSize: CGSize
    let padding: CGFloat
    let spacing: CGFloat
    let cornerRadius: CGFloat
    let tileRadius: CGFloat

    var size: CGSize {
        CGSize(width: tileSize.width + 2 * padding, height: 4 * tileSize.height + 3 * spacing + 2 * padding)
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
