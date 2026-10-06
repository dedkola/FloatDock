import AppKit
import FloatDockCore
import SwiftUI

struct DockView: View {
    let store: MetricsStore
    let appearance: AppearanceSettings
    let select: (MetricKind) -> Void
    let registerAnchor: (MetricKind, NSView) -> Void
    @FocusState private var focused: MetricKind?
    @Environment(\.controlActiveState) private var controlActivity
    private let kinds: [MetricKind] = [.cpu, .memory, .gpu, .network]

    var body: some View {
        let layout = appearance.design.layout
        VStack(spacing: layout.spacing) {
            ForEach(kinds, id: \.self) { kind in
                MetricTile(kind: kind, design: appearance.design, store: store,
                           selected: store.selected == kind, focused: focused == kind && controlActivity == .key) { select(kind) }
                    .background(AnchorView(kind: kind, register: registerAnchor))
                    .focused($focused, equals: kind)
                    .onKeyPress(.return) { select(kind); return .handled }
                    .onKeyPress(.space) { select(kind); return .handled }
                    .onMoveCommand { direction in
                        guard let index = kinds.firstIndex(of: kind) else { return }
                        if direction == .up { focused = kinds[max(0, index - 1)] }
                        if direction == .down { focused = kinds[min(3, index + 1)] }
                    }
            }
        }
        .padding(layout.padding)
        .frame(width: layout.size.width, height: layout.size.height)
        .onChange(of: store.focusRequest) { focused = store.focusTarget }
        .onChange(of: focused) { if let focused { store.focusTarget = focused } }
        .onChange(of: appearance.design) { focused = nil }
    }
}

struct MetricTile: View {
    let kind: MetricKind
    let design: DockDesign
    let store: MetricsStore
    let selected: Bool
    let focused: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovering = false

    private var accent: Color { kind.color(scheme) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: design.layout.tileRadius, style: .continuous) }

    var body: some View {
        Button(action: action) {
            content
                .frame(width: design.layout.tileSize.width, height: design.layout.tileSize.height)
                .background {
                    shape.fill(cardFill)
                        .overlay(shape.strokeBorder(cardEdge, lineWidth: 0.7))
                        .shadow(color: .black.opacity(scheme == .dark ? 0.18 : 0.10), radius: 2, x: 0, y: 1)
                }
                .overlay {
                    if selected { shape.strokeBorder(accent.opacity(0.7), lineWidth: 1.2) }
                    if focused { shape.strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2) }
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable()
        .focusEffectDisabled()
        .frame(width: design.layout.tileSize.width, height: design.layout.tileSize.height)
        .onHover { hovering = $0 }
        .help(kind.title)
        .accessibilityLabel(kind.title)
        .accessibilityValue(store.accessibilityValue(for: kind))
        .accessibilityHint(selected ? "Close details" : "Show details")
        .accessibilityIdentifier("widget.\(kind.shortTitle.lowercased())")
        .accessibilityElement(children: .ignore)
    }

    private var cardFill: LinearGradient {
        // Cards keep a readable surface of their own over the clear outer dock.
        // The material sliders never change card or foreground opacity.
        let emphasis = selected || hovering ? 0.08 : 0.0
        let top = contrast == .increased ? 0.96 : 0.78
        let bottom = contrast == .increased ? 0.90 : 0.64
        let surface = scheme == .dark ? Color(nsColor: .underPageBackgroundColor) : .white
        return LinearGradient(colors: [surface.opacity(min(1, top + emphasis)), surface.opacity(min(1, bottom + emphasis))],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var cardEdge: LinearGradient {
        LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.25 : 0.82),
                                .black.opacity(scheme == .dark ? 0.25 : 0.13)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @ViewBuilder private var content: some View {
        switch design {
        case .current: currentContent
        case .float: floatContent
        case .orbit: orbitContent
        case .ribbon: ribbonContent
        }
    }

    private func label(symbol: Bool = false) -> some View {
        HStack(spacing: 3) {
            if symbol { Image(systemName: kind.symbol).foregroundStyle(accent).font(.system(size: 9)) }
            Text(kind.shortTitle).foregroundStyle(.secondary)
        }
        .font(.system(size: design == .current ? 9 : 8, weight: .medium))
        .tracking(0.15)
    }

    private func percentage(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(ValueFormat.percent(store.currentPercent(kind)))
                .font(.system(size: size, weight: .medium))
                .tracking(-0.4)
            if store.currentPercent(kind) != nil {
                Text("%").font(.system(size: size > 21 ? 10 : 9, weight: .regular))
            }
        }
        .monospacedDigit()
        .foregroundStyle(.primary)
    }

    private var currentContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            label()
            CurrentMetricGlyph(kind: kind, value: store.currentPercent(kind), network: store.networkCurrent,
                               accent: accent, secondary: MetricKind.memory.color(scheme),
                               animated: store.animationsActive && !reduceMotion)
                .frame(maxWidth: .infinity)
                .frame(height: kind == .network ? 26 : 31)
                .accessibilityHidden(true)
            if kind == .network { networkValues(primarySize: 11, secondarySize: 9, spacing: 2) }
            else { percentage(size: 20) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var floatContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            label(symbol: true)
            if kind == .network { networkValues(primarySize: 11, secondarySize: 9, spacing: 3) }
            else { percentage(size: 24) }
            Spacer(minLength: 1)
            sparkline.frame(height: 12)
        }
        .padding(9)
    }

    private var orbitContent: some View {
        ZStack {
            Circle().strokeBorder(accent.opacity(0.13), lineWidth: 2.2).padding(6)
            if kind == .network {
                gauge(store.networkCurrent.map { $0.receiveBytesPerSecond / store.networkScale }, inset: 6, color: accent)
                gauge(store.networkCurrent.map { $0.sendBytesPerSecond / store.networkScale }, inset: 10, color: MetricKind.memory.color(scheme))
            } else { gauge(store.currentPercent(kind).map { $0 / 100 }, inset: 6, color: accent) }
            VStack(spacing: 3) {
                if kind == .network { networkValues(primarySize: 9, secondarySize: 8, spacing: 2) }
                else { percentage(size: 20) }
                label()
            }
        }
        .padding(1)
    }

    private func gauge(_ fraction: Double?, inset: CGFloat, color: Color) -> some View {
        Circle().trim(from: 0, to: min(1, max(0, fraction ?? 0)))
            .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: inset > 6 ? 1.4 : 2.2, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(inset)
            .animation(reduceMotion || !store.animationsActive ? nil : .easeInOut(duration: 0.75), value: fraction)
            .accessibilityHidden(true)
    }

    private var ribbonContent: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                label()
                Spacer(minLength: 0)
                if kind == .network { networkValues(primarySize: 9, secondarySize: 8, spacing: 2) }
                else { percentage(size: 17) }
            }
            Spacer(minLength: 0)
            if kind == .network { sparkline.frame(height: 12) }
            else {
                HStack(spacing: 3) {
                    ForEach(0..<13) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(accent.opacity((store.currentPercent(kind) ?? 0) >= Double(index + 1) / 13 * 100 ? 0.8 : 0.14))
                    }
                }
                .frame(height: 13)
                .animation(reduceMotion || !store.animationsActive ? nil : .easeInOut(duration: 0.75), value: store.currentPercent(kind))
                .accessibilityHidden(true)
            }
        }
        .padding(9)
    }

    private var sparkline: some View {
        HistoryChart(kind: kind, points: store.points(for: kind),
                     totalMemory: Double(store.snapshot?.memory.lastValue?.totalBytes ?? 1),
                     now: store.snapshot?.timestamp ?? Date(), compact: true)
    }

    private func networkValues(primarySize: CGFloat, secondarySize: CGFloat, spacing: CGFloat) -> some View {
        VStack(alignment: design == .orbit ? .center : .leading, spacing: spacing) {
            networkRow("arrow.down", store.networkCurrent?.receiveBytesPerSecond, size: primarySize, color: accent)
            networkRow("arrow.up", store.networkCurrent?.sendBytesPerSecond, size: secondarySize, color: MetricKind.memory.color(scheme))
        }
    }

    private func networkRow(_ symbol: String, _ value: Double?, size: CGFloat, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol).foregroundStyle(color).font(.system(size: max(7, size - 1)))
            Text(value.map(ValueFormat.rate) ?? "—").foregroundStyle(.primary).lineLimit(1)
        }
        .font(.system(size: size, weight: .medium))
        .monospacedDigit()
        .minimumScaleFactor(0.72)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct AnchorView: NSViewRepresentable {
    let kind: MetricKind
    let register: (MetricKind, NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NonInteractiveAnchor()
        register(kind, view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { register(kind, nsView) }
}

final class NonInteractiveAnchor: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct MetricDetailView: View {
    let kind: MetricKind
    let store: MetricsStore
    let close: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(kind.title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).frame(width: 24, height: 24) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Close details")
                    .accessibilityLabel("Close details")
                    .accessibilityIdentifier("popover.close")
            }
            detailContent
            if let status = store.status(for: kind) {
                Text(status).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .accessibilityIdentifier("popover.\(kind.shortTitle.lowercased())")
    }

    @ViewBuilder private var detailContent: some View {
        switch kind {
        case .cpu:
            if let value = store.snapshot?.cpu.lastValue {
                mainValue(String(format: "%.1f", value.busyPercent), unit: "%", subtitle: "Total CPU usage")
                chart
                detailRows([("User", percentage(value.userPercent)), ("System", percentage(value.systemPercent)), ("Idle", percentage(value.idlePercent))])
            } else { unknownValue }
        case .memory:
            if let value = store.snapshot?.memory.lastValue {
                mainValue(String(format: "%.1f", Double(value.usedBytes) / 1_073_741_824), unit: "/ \(ValueFormat.gib(value.totalBytes))", subtitle: "Used memory · estimate")
                    .help("Estimated from macOS VM counters; may differ from Activity Monitor.")
                chart
                detailRows([("Wired", ValueFormat.gib(value.wiredBytes)), ("Compressed", ValueFormat.gib(value.compressedBytes)), ("Swap used", value.swapUsedBytes.map(ValueFormat.gib) ?? "—")])
            } else { unknownValue }
        case .gpu:
            if let value = store.snapshot?.gpu.lastValue {
                mainValue(String(format: "%.1f", value.utilizationPercent), unit: "%", subtitle: "GPU utilization")
                chart
                detailRows([("Device", value.name)])
            } else { unknownValue }
        case .network:
            if let value = store.snapshot?.network.lastValue {
                HStack(alignment: .top, spacing: 20) {
                    rateValue(value.receiveBytesPerSecond, symbol: "arrow.down", title: "Receive · solid", color: MetricKind.network.color(scheme))
                    rateValue(value.sendBytesPerSecond, symbol: "arrow.up", title: "Send · dashed", color: MetricKind.memory.color(scheme))
                }
                chart
                detailRows([("Interface", "\(value.interfaceLabel) · \(value.interfaceName)"), ("Received", ValueFormat.total(value.receivedSessionBytes)), ("Sent", ValueFormat.total(value.sentSessionBytes))])
                Text("Since app launch · monitored interface traffic").font(.system(size: 10)).foregroundStyle(.secondary)
            } else { unknownValue }
        }
    }

    private var unknownValue: some View {
        Text("—").font(.system(size: 28, weight: .medium)).padding(.vertical, 8)
    }
    private var chart: some View {
        HistoryChart(kind: kind, points: store.points(for: kind), totalMemory: Double(store.snapshot?.memory.lastValue?.totalBytes ?? 1), now: store.snapshot?.timestamp ?? Date())
    }
    private func mainValue(_ value: String, unit: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 28, weight: .medium))
                Text(unit).font(.system(size: 13))
            }.monospacedDigit()
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    private func percentage(_ value: Double) -> String { String(format: "%.1f%%", value) }
    private func detailRows(_ rows: [(String, String)]) -> some View {
        VStack(spacing: 8) {
            Divider().padding(.bottom, 2)
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.0).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(row.1).fontWeight(.medium).multilineTextAlignment(.trailing)
                }.font(.system(size: 12)).monospacedDigit()
            }
        }
    }
    private func rateValue(_ value: Double, symbol: String, title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ValueFormat.rate(value)).font(.system(size: 21, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            Label(title, systemImage: symbol).font(.system(size: 10)).foregroundStyle(color)
        }
    }
}
