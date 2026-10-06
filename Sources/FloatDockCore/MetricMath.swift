import Foundation
import CoreFoundation

public struct CPUTicks: Sendable, Equatable {
    public let user: UInt32
    public let system: UInt32
    public let idle: UInt32
    public let nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
}

public enum MetricMath {
    /// A backwards jump is accepted only at the boundary of the 32-bit counter.
    /// Resets elsewhere are discontinuities, not wraparounds.
    public static func tickDelta(_ old: UInt32, _ new: UInt32) -> UInt64? {
        if new >= old { return UInt64(new - old) }
        guard old > UInt32.max - UInt32.max / 8, new < UInt32.max / 8 else { return nil }
        return UInt64(new &- old)
    }

    public static func cpu(previous: CPUTicks, current: CPUTicks) -> CPUValue? {
        guard let user = tickDelta(previous.user, current.user),
              let system = tickDelta(previous.system, current.system),
              let idle = tickDelta(previous.idle, current.idle),
              let nice = tickDelta(previous.nice, current.nice) else { return nil }
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        let denominator = Double(total)
        return CPUValue(busyPercent: Double(total - idle) / denominator * 100,
                        userPercent: Double(user + nice) / denominator * 100,
                        systemPercent: Double(system) / denominator * 100,
                        idlePercent: Double(idle) / denominator * 100)
    }

    public static func memory(active: UInt64, inactive: UInt64, speculative: UInt64, wired: UInt64, compressor: UInt64, purgeable: UInt64, external: UInt64, pageSize: UInt64, totalBytes: UInt64, swapUsedBytes: UInt64?) -> MemoryValue? {
        guard pageSize > 0, totalBytes > 0 else { return nil }
        // Decimal arithmetic avoids unsigned subtraction and caller-supplied overflow.
        let pages = Decimal(active) + Decimal(inactive) + Decimal(speculative) + Decimal(wired)
            + Decimal(compressor) - Decimal(purgeable) - Decimal(external)
        let used = pages * Decimal(pageSize)
        let wiredAmount = Decimal(wired) * Decimal(pageSize)
        let compressedAmount = Decimal(compressor) * Decimal(pageSize)
        guard used >= 0, used <= Decimal(totalBytes), wiredAmount <= Decimal(totalBytes), compressedAmount <= Decimal(totalBytes) else { return nil }
        return MemoryValue(usedBytes: NSDecimalNumber(decimal: used).uint64Value,
                           totalBytes: totalBytes,
                           wiredBytes: NSDecimalNumber(decimal: wiredAmount).uint64Value,
                           compressedBytes: NSDecimalNumber(decimal: compressedAmount).uint64Value,
                           swapUsedBytes: swapUsedBytes)
    }

    public static func rate(previous: UInt64, current: UInt64, elapsed: TimeInterval) -> Double? {
        guard elapsed.isFinite, elapsed > 0, elapsed <= 3, current >= previous else { return nil }
        return Double(current - previous) / elapsed
    }

    /// The validated Apple Silicon accelerator field reports an actual percent.
    /// Reject booleans, absent fields, strings, NaN, and values outside its unit range.
    public static func gpuPercent(statistics: [String: Any]) -> Double? {
        guard let number = statistics["Device Utilization %"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }
}

/// Records missing samples as actual gaps rather than compressing elapsed time.
public struct HistoryPoint: Sendable, Equatable {
    public let timestamp: Date
    public let value: Double?
    public init(timestamp: Date, value: Double?) { self.timestamp = timestamp; self.value = value }
}

public struct HistoryBuffer: Sendable {
    public private(set) var points: [HistoryPoint] = []
    public let capacity: Int
    public let duration: TimeInterval

    public init(capacity: Int = 61, duration: TimeInterval = 60) {
        self.capacity = max(1, capacity)
        self.duration = max(0, duration)
    }

    public mutating func append(_ point: HistoryPoint) {
        // A clock adjustment must not fabricate an out-of-order graph.
        if let previous = points.last, point.timestamp < previous.timestamp { points.removeAll(keepingCapacity: true) }
        points.append(point)
        prune(now: point.timestamp)
    }

    public mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-duration)
        points.removeAll { $0.timestamp < cutoff }
        if points.count > capacity { points.removeFirst(points.count - capacity) }
    }
}
