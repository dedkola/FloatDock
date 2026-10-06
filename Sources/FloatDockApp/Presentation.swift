import AppKit
import FloatDockCore
import Observation
import SwiftUI

@MainActor @Observable
final class MetricsStore {
    var snapshot: SystemSnapshot?
    var selected: MetricKind?
    var focusRequest = 0
    var focusTarget: MetricKind = .cpu
    var animationsActive = true
    private var series = SegmentedHistory()
    var history: [HistorySample] { series.samples }

    func update(_ snapshot: SystemSnapshot) {
        self.snapshot = snapshot
        let now = snapshot.timestamp
        if let cpu = snapshot.cpu.value { series.append(kind: .cpu, value: cpu.busyPercent, at: now) }
        else { series.markMissing(kind: .cpu) }
        if let memory = snapshot.memory.value { series.append(kind: .memory, value: Double(memory.usedBytes), at: now) }
        else { series.markMissing(kind: .memory) }
        if let gpu = snapshot.gpu.value { series.append(kind: .gpu, value: gpu.utilizationPercent, at: now) }
        else { series.markMissing(kind: .gpu) }
        if let network = snapshot.network.value {
            series.append(kind: .network, value: network.receiveBytesPerSecond, secondary: network.sendBytesPerSecond, at: now)
        } else { series.markMissing(kind: .network) }
        series.prune(now: now)
    }

    func points(for kind: MetricKind) -> [HistorySample] { history.filter { $0.kind == kind } }
    func interruptHistory() { series.interrupt() }
    var networkCurrent: NetworkValue? { snapshot.flatMap { tileValue($0.network) } }
    // A shared observed range, never a claim about the link's capacity.
    var networkScale: Double {
        max(1000, (points(for: .network).map { max($0.value, $0.secondary ?? 0) }.max() ?? 0) * 1.1)
    }

    private func tileValue<Value>(_ reading: MetricReading<Value>) -> Value? {
        if let value = reading.value { return value }
        if case let .stale(value, date) = reading, Date().timeIntervalSince(date) < 3 { return value }
        return nil
    }
    func currentPercent(_ kind: MetricKind) -> Double? {
        guard let snapshot else { return nil }
        switch kind {
        case .cpu: return tileValue(snapshot.cpu)?.busyPercent
        case .memory:
            guard let value = tileValue(snapshot.memory), value.totalBytes > 0 else { return nil }
            return Double(value.usedBytes) / Double(value.totalBytes) * 100
        case .gpu: return tileValue(snapshot.gpu)?.utilizationPercent
        case .network: return nil
        }
    }

    func status(for kind: MetricKind) -> String? {
        guard let snapshot else { return "Collecting first sample…" }
        switch kind {
        case .cpu: return readingStatus(snapshot.cpu)
        case .memory: return readingStatus(snapshot.memory)
        case .gpu: return readingStatus(snapshot.gpu)
        case .network: return readingStatus(snapshot.network)
        }
    }

    private func readingStatus<Value>(_ reading: MetricReading<Value>) -> String? {
        switch reading {
        case .warmingUp: return "Collecting first sample…"
        case .available: return nil
        case .stale(_, let date): return "Last updated \(max(0, Int(Date().timeIntervalSince(date)))) seconds ago"
        case .unavailable(let reason): return reason
        }
    }

    func accessibilityValue(for kind: MetricKind) -> String {
        if kind == .network, let network = networkCurrent {
            return "receiving \(ValueFormat.rate(network.receiveBytesPerSecond)), sending \(ValueFormat.rate(network.sendBytesPerSecond))"
        }
        if let value = currentPercent(kind) { return "\(Int(value.rounded())) percent" }
        return status(for: kind) ?? "Unavailable"
    }
}

typealias HistorySample = HistorySeriesSample

enum ValueFormat {
    static func percent(_ value: Double?) -> String { value.map { String(format: "%.0f", $0) } ?? "—" }
    static func gib(_ bytes: UInt64) -> String { String(format: "%.1f GiB", Double(bytes) / 1_073_741_824) }
    static func rate(_ bytes: Double) -> String { decimal(bytes, suffix: "/s") }
    static func total(_ bytes: UInt64) -> String { decimal(Double(bytes), suffix: "") }
    private static func decimal(_ value: Double, suffix: String) -> String {
        guard value.isFinite, value >= 0 else { return "—" }
        let units = ["B", "kB", "MB", "GB", "TB"]
        var scaled = value
        var index = 0
        while scaled >= 1000, index < units.count - 1 { scaled /= 1000; index += 1 }
        let number = scaled >= 100 || index == 0 ? String(format: "%.0f", scaled) : String(format: "%.1f", scaled)
        return "\(number) \(units[index])\(suffix)"
    }
}

extension MetricKind {
    var title: String {
        switch self { case .cpu: "CPU"; case .memory: "Memory"; case .gpu: "GPU"; case .network: "Network" }
    }
    var shortTitle: String {
        switch self { case .cpu: "CPU"; case .memory: "MEM"; case .gpu: "GPU"; case .network: "NET" }
    }
    var symbol: String {
        switch self { case .cpu: "cpu"; case .memory: "memorychip"; case .gpu: "square.3.layers.3d"; case .network: "arrow.up.arrow.down" }
    }
    func color(_ scheme: ColorScheme) -> Color {
        let hex: UInt32 = switch self {
        case .cpu: scheme == .dark ? 0x91B6F0 : 0x447DD3
        case .memory: scheme == .dark ? 0xC5A7E9 : 0x9270BD
        case .gpu: scheme == .dark ? 0x86CEBA : 0x358C7D
        case .network: scheme == .dark ? 0x8FC6DD : 0x3B8FA9
        }
        return Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}
