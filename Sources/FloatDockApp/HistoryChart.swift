import Charts
import FloatDockCore
import SwiftUI

struct HistoryChart: View {
    let kind: MetricKind
    let points: [HistorySample]
    let totalMemory: Double
    let now: Date
    var compact = false
    @Environment(\.colorScheme) private var scheme

    private var maximum: Double {
        switch kind {
        case .cpu, .gpu: 100
        case .memory: max(1, totalMemory)
        case .network: max(1000, (points.map { max($0.value, $0.secondary ?? 0) }.max() ?? 0) * 1.1)
        }
    }

    @ViewBuilder
    var body: some View {
        if compact {
            sparkline
                .frame(height: 12)
                .accessibilityHidden(true)
        } else {
            detailChart
        }
    }

    // A tiny 48×12 sparkline needs only a few path segments. Keeping the full
    // Charts layout in the open detail window reduces steady dock CPU usage.
    private var sparkline: some View {
        let primary = kind.color(scheme)
        let secondary = MetricKind.memory.color(scheme)
        let ceiling = maximum
        return Canvas { context, size in
            func path(sent: Bool) -> Path {
                var result = Path()
                var previousSegment: Int?
                for sample in points {
                    guard let value = sent ? sample.secondary : sample.value else { continue }
                    let elapsed = sample.date.timeIntervalSince(now.addingTimeInterval(-60))
                    let x = elapsed / 60 * size.width
                    let y = 0.6 + (1 - value / ceiling) * max(0, size.height - 1.2)
                    let point = CGPoint(x: x, y: y)
                    if sample.segment == previousSegment { result.addLine(to: point) }
                    else { result.move(to: point) }
                    previousSegment = sample.segment
                }
                return result
            }
            context.stroke(path(sent: false), with: .color(primary), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            if kind == .network {
                context.stroke(path(sent: true), with: .color(secondary), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
            }
        }
        .clipped()
    }

    private var detailChart: some View {
        VStack(spacing: 6) {
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Time", point.date), y: .value("Value", point.value), series: .value("Segment", "receive-\(point.segment)"))
                        .foregroundStyle(kind.color(scheme))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    if kind == .network, let sent = point.secondary {
                        LineMark(x: .value("Time", point.date), y: .value("Value", sent), series: .value("Segment", "send-\(point.segment)"))
                            .foregroundStyle(MetricKind.memory.color(scheme))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                }
            }
            .chartXScale(domain: now.addingTimeInterval(-60)...now)
            .chartYScale(domain: 0...maximum)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartPlotStyle { plot in
                plot.background {
                    VStack { Divider(); Spacer(); Divider(); Spacer(); Divider() }
                        .opacity(0.35)
                }
            }
            .frame(height: 78)
            HStack {
                Text("60s ago")
                Spacer()
                Text(scaleLabel)
                Spacer()
                Text("Now")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title) history")
        .accessibilityValue(summary)
    }

    private var scaleLabel: String {
        switch kind {
        case .cpu, .gpu: "100% scale"
        case .memory: "\(ValueFormat.gib(UInt64(max(0, totalMemory)))) scale"
        case .network: "\(ValueFormat.rate(maximum)) scale"
        }
    }

    private var summary: String {
        guard let latest = points.last else { return "No samples yet" }
        let low = points.map(\.value).min() ?? latest.value
        let high = points.map(\.value).max() ?? latest.value
        func formatted(_ value: Double) -> String {
            switch kind {
            case .cpu, .gpu: "\(ValueFormat.percent(value)) percent"
            case .memory: ValueFormat.gib(UInt64(max(0, value)))
            case .network: ValueFormat.rate(value)
            }
        }
        let primary = "Latest \(formatted(latest.value)), minimum \(formatted(low)), maximum \(formatted(high)) over available history."
        guard kind == .network else { return primary }
        let sent = points.compactMap(\.secondary)
        return "Receive: \(primary) Send: latest \(ValueFormat.rate(latest.secondary ?? 0)), minimum \(ValueFormat.rate(sent.min() ?? 0)), maximum \(ValueFormat.rate(sent.max() ?? 0))."
    }
}
