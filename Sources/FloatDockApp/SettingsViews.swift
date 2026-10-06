import AppKit
import SwiftUI

@MainActor
struct SettingsView: View {
    @Bindable var appearance: AppearanceSettings
    @State private var section: SettingsSection? = .appearance

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Label("Appearance", systemImage: "paintpalette")
                    .tag(SettingsSection.appearance)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 145, ideal: 160, max: 190)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Appearance")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Adjust the dock material and choose a design. Changes apply immediately.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .padding(.top, 28)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        MaterialControls(appearance: appearance)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(DockDesign.allCases) { design in
                                DesignSelectionCard(design: design, selected: appearance.design == design) {
                                    appearance.design = design
                                }
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .accessibilityIdentifier("settings.window")
    }
}

private enum SettingsSection: Hashable {
    case appearance
}

@MainActor
private struct MaterialControls: View {
    @Bindable var appearance: AppearanceSettings
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GroupBox("Materials") {
            VStack(alignment: .leading, spacing: 16) {
                MaterialSliderRow(
                    title: "Transparency",
                    value: $appearance.transparency,
                    minimumLabel: "Opaque",
                    maximumLabel: "Clear",
                    identifier: "settings.material.transparency"
                )
                .disabled(reduceTransparency)
                MaterialSliderRow(
                    title: "Liquid Glass",
                    value: $appearance.glassStrength,
                    minimumLabel: "Off",
                    maximumLabel: "Full",
                    identifier: "settings.material.glassStrength"
                )
                .disabled(reduceTransparency)
                HStack {
                    Text(reduceTransparency
                         ? "Reduce Transparency is on in macOS. The dock stays opaque."
                         : "Clear shows your wallpaper. Widget cards keep their own surface.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset to Defaults") {
                        appearance.resetMaterialDefaults()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appearance.transparency == 1 && appearance.glassStrength == 1)
                    .accessibilityHint("Reset Transparency and Liquid Glass to 100 percent")
                    .accessibilityIdentifier("settings.material.reset")
                }
            }
            .padding(8)
        }
    }
}

private struct MaterialSliderRow: View {
    let title: String
    @Binding var value: Double
    let minimumLabel: String
    let maximumLabel: String
    let identifier: String

    private var percentage: String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(percentage)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)

            NativeMaterialSlider(value: $value, title: title, identifier: identifier)
                .frame(height: 22)

            HStack {
                Text(minimumLabel)
                Spacer()
                Text(maximumLabel)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }
}

/// AppKit supplies the native slider's tracking, keyboard behavior and AX value.
@MainActor
private struct NativeMaterialSlider: NSViewRepresentable {
    @Binding var value: Double
    let title: String
    let identifier: String
    @Environment(\.isEnabled) private var enabled

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: 0, maxValue: 1,
                              target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.isContinuous = true
        slider.controlSize = .regular
        slider.numberOfTickMarks = 0
        slider.setAccessibilityLabel(title)
        slider.setAccessibilityHelp("Changes apply immediately")
        slider.setAccessibilityIdentifier(identifier)
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        slider.doubleValue = value
        slider.isEnabled = enabled
    }

    @MainActor
    final class Coordinator: NSObject {
        var value: Binding<Double>
        init(value: Binding<Double>) { self.value = value }
        @objc func changed(_ slider: NSSlider) { value.wrappedValue = slider.doubleValue }
    }
}

private struct DesignSelectionCard: View {
    let design: DockDesign
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DesignMiniPreview(design: design)
                .accessibilityHidden(true)

            HStack {
                Text(design.title).font(.system(size: 13, weight: .semibold))
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }

            Text(design.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(minHeight: 26, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)

            Button(selected ? "Selected" : "Use \(design.title)", action: choose)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selected)
                .accessibilityLabel("\(design.title) dock design")
                .accessibilityValue(selected ? "Selected" : "Not selected")
                .accessibilityHint(selected ? "Current appearance" : "Apply this design immediately")
                .accessibilityIdentifier("settings.design.\(design.rawValue)")
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.65) : Color(nsColor: .separatorColor).opacity(0.6), lineWidth: selected ? 1.5 : 1)
        }
    }
}

/// Static sample artwork is confined to Settings; it never enters the live store.
private struct DesignMiniPreview: View {
    let design: DockDesign
    private let scale: CGFloat = 0.32
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.blue.opacity(scheme == .dark ? 0.16 : 0.19), Color.teal.opacity(0.09), Color(nsColor: .windowBackgroundColor)],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                ))

            VStack(spacing: design.layout.spacing) {
                ForEach(PreviewMetric.allCases) { metric in
                    DesignPreviewTile(design: design, metric: metric)
                        .frame(width: design.layout.tileSize.width, height: design.layout.tileSize.height)
                }
            }
            .padding(design.layout.padding)
            .frame(width: design.layout.size.width, height: design.layout.size.height)
            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: design.layout.cornerRadius, style: .continuous))
            .scaleEffect(scale)
            .frame(width: design.layout.size.width * scale, height: design.layout.size.height * scale)
        }
        .frame(height: 142)
        .overlay(alignment: .topLeading) {
            Text("Preview · sample values")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }
}

private enum PreviewMetric: CaseIterable, Identifiable, Hashable, Sendable {
    case cpu, memory, gpu, network
    var id: Self { self }
    var label: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "MEM"
        case .gpu: "GPU"
        case .network: "NET"
        }
    }
    var percent: Double {
        switch self {
        case .cpu: 24
        case .memory: 63
        case .gpu: 12
        case .network: 48
        }
    }
    var color: Color {
        switch self {
        case .cpu: Color(red: 0.27, green: 0.49, blue: 0.83)
        case .memory: Color(red: 0.57, green: 0.44, blue: 0.74)
        case .gpu: Color(red: 0.21, green: 0.55, blue: 0.49)
        case .network: Color(red: 0.23, green: 0.56, blue: 0.66)
        }
    }
}

private struct DesignPreviewTile: View {
    let design: DockDesign
    let metric: PreviewMetric
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            switch design {
            case .current: current
            case .float: float
            case .orbit: orbit
            case .ribbon: ribbon
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background((scheme == .dark ? Color(nsColor: .underPageBackgroundColor) : .white).opacity(0.72), in: RoundedRectangle(cornerRadius: design.layout.tileRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: design.layout.tileRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.7)
        }
    }

    private var label: some View {
        Text(metric.label).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
    }

    @ViewBuilder private func reading(size: CGFloat, networkAlignment: HorizontalAlignment = .leading) -> some View {
        if metric == .network {
            VStack(alignment: networkAlignment, spacing: 3) {
                Text("↓ 1.2 MB/s").font(.system(size: networkPrimarySize, weight: .medium))
                Text("↑ 84 kB/s").font(.system(size: networkSecondarySize, weight: .medium)).foregroundStyle(.secondary)
            }
            .monospacedDigit()
        } else {
            Text("\(Int(metric.percent))%")
                .font(.system(size: size, weight: .medium))
                .monospacedDigit()
        }
    }

    private var networkPrimarySize: CGFloat {
        switch design {
        case .current, .float: 11
        case .orbit, .ribbon: 9
        }
    }

    private var networkSecondarySize: CGFloat {
        switch design {
        case .current, .float: 9
        case .orbit, .ribbon: 8
        }
    }

    private var current: some View {
        VStack(alignment: .leading, spacing: 4) {
            label
            PreviewKineticGlyph(metric: metric).frame(height: 26)
            reading(size: 20)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var float: some View {
        VStack(alignment: .leading, spacing: 6) {
            label
            reading(size: 23)
            Spacer(minLength: 12)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) {
            PreviewTrace(color: metric.color, filled: true).frame(height: 32)
        }
        .clipShape(RoundedRectangle(cornerRadius: design.layout.tileRadius, style: .continuous))
    }

    private var orbit: some View {
        ZStack {
            Circle().stroke(metric.color.opacity(0.13), lineWidth: 2.3).padding(5)
            Circle().trim(from: 0, to: metric.percent / 100)
                .stroke(metric.color, style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(5)
            if metric == .network {
                Circle().trim(from: 0, to: 0.3)
                    .stroke(PreviewMetric.memory.color, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [3, 2]))
                    .rotationEffect(.degrees(-90)).padding(10)
            }
            VStack(spacing: 3) {
                reading(size: 19, networkAlignment: .center)
                Text(metric.label).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }

    private var ribbon: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                label
                Spacer(minLength: 2)
                reading(size: 17, networkAlignment: .trailing)
            }
            if metric == .network {
                PreviewTrace(color: metric.color, filled: false).frame(height: 11)
            } else {
                HStack(spacing: 2) {
                    ForEach(0..<13, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(metric.color.opacity(Double(index + 1) / 13 * 100 <= metric.percent ? 0.8 : 0.12))
                            .frame(height: 12)
                    }
                }
            }
        }
        .padding(9)
    }
}

private struct PreviewTrace: View {
    let color: Color
    let filled: Bool

    var body: some View {
        Canvas { context, size in
            let levels: [CGFloat] = [0.62, 0.60, 0.71, 0.46, 0.57, 0.40, 0.48, 0.24, 0.37, 0.35, 0.54, 0.42]
            let points = levels.enumerated().map { index, level in
                CGPoint(x: CGFloat(index) / CGFloat(levels.count - 1) * size.width, y: level * size.height)
            }
            var line = Path()
            line.addLines(points)
            if filled {
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .color(color.opacity(0.12)))
            }
            context.stroke(line, with: .color(color.opacity(0.8)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct PreviewKineticGlyph: View {
    let metric: PreviewMetric

    var body: some View {
        Canvas { context, size in
            switch metric {
            case .cpu:
                let levels: [CGFloat] = [0.48, 0.48, 0.32, 0.61, 0.08, 0.89, 0.43, 0.45, 0.55, 0.45, 0.49]
                var line = Path()
                line.addLines(levels.enumerated().map { index, level in
                    CGPoint(x: CGFloat(index) / CGFloat(levels.count - 1) * size.width, y: level * size.height)
                })
                context.stroke(line, with: .color(metric.color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            case .memory:
                for layer in 0..<3 {
                    var drawing = context
                    drawing.translateBy(x: size.width / 2, y: 19 - CGFloat(layer) * 5)
                    drawing.rotate(by: .degrees(-24))
                    drawing.scaleBy(x: 1, y: 0.5)
                    let shape = Path(roundedRect: CGRect(x: -18, y: -11, width: 36, height: 22), cornerRadius: 5)
                    drawing.fill(shape, with: .color(metric.color.opacity(0.08 + Double(layer) * 0.05)))
                    drawing.stroke(shape, with: .color(metric.color.opacity(0.35 + Double(layer) * 0.23)), lineWidth: 1.2)
                }
            case .gpu:
                let offset = CGPoint(x: (size.width - 40) / 2, y: (size.height - 26) / 2)
                for index in 0..<12 {
                    let rect = CGRect(x: offset.x + CGFloat(index % 4) * 11, y: offset.y + CGFloat(index / 4) * 9, width: 7, height: 7)
                    let lit = index < Int(ceil(metric.percent / 100 * 12))
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(metric.color.opacity(lit ? 0.85 : 0.15)))
                }
            case .network:
                for lane in 0..<2 {
                    let y = size.height * (lane == 0 ? 0.33 : 0.68)
                    let color = lane == 0 ? metric.color : PreviewMetric.memory.color
                    var track = Path()
                    track.move(to: CGPoint(x: 4, y: y))
                    track.addLine(to: CGPoint(x: size.width - 4, y: y))
                    context.stroke(track, with: .color(color.opacity(0.22)), lineWidth: 1)
                    let packet = CGRect(x: size.width * (lane == 0 ? 0.25 : 0.58), y: y - 1.5, width: 11, height: 3)
                    context.fill(Path(roundedRect: packet, cornerRadius: 1.5), with: .color(color.opacity(0.8)))
                }
            }
        }
    }
}
