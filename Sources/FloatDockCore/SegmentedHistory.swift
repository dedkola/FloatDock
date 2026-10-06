import Foundation

/// Actual valid observations only. Segment boundaries tell chart renderers not
/// to draw through missing polls or across paused sampling sessions.
public struct HistorySeriesSample: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let kind: MetricKind
    public let date: Date
    public let value: Double
    public let secondary: Double?
    public let segment: Int

    public init(id: UUID = UUID(), kind: MetricKind, date: Date, value: Double, secondary: Double? = nil, segment: Int) {
        self.id = id
        self.kind = kind
        self.date = date
        self.value = value
        self.secondary = secondary
        self.segment = segment
    }
}

public struct SegmentedHistory: Sendable {
    public private(set) var samples: [HistorySeriesSample] = []
    public let duration: TimeInterval
    public let capacity: Int
    private var segments: [MetricKind: Int] = [:]
    private var lastDate: Date?
    private var lastValidDate: [MetricKind: Date] = [:]

    /// At 1 Hz four series have at most 244 observations including both ends of
    /// the trailing 60-second window. Capacity also bounds pathological callers.
    public init(duration: TimeInterval = 60, capacity: Int = 244) {
        self.duration = max(0, duration)
        self.capacity = max(1, capacity)
    }

    public mutating func append(kind: MetricKind, value: Double, secondary: Double? = nil, at date: Date) {
        guard value.isFinite, secondary?.isFinite != false else {
            markMissing(kind: kind)
            prune(now: date)
            return
        }
        reconcileClock(now: date)
        // A stalled actor can return a successful memory/GPU reading without a
        // missing-state callback. Preserve that unobserved interval as a gap.
        if let previous = lastValidDate[kind], date.timeIntervalSince(previous) > 2.5 {
            markMissing(kind: kind)
        }
        lastValidDate[kind] = date
        samples.append(HistorySeriesSample(kind: kind, date: date, value: value, secondary: secondary,
                                           segment: segments[kind, default: 0]))
        prune(now: date)
    }

    public mutating func markMissing(kind: MetricKind) {
        segments[kind, default: 0] &+= 1
    }

    public mutating func interrupt() {
        for kind in MetricKind.allCases { markMissing(kind: kind) }
    }

    public mutating func prune(now: Date) {
        reconcileClock(now: now)
        let cutoff = now.addingTimeInterval(-duration)
        samples.removeAll { $0.date < cutoff }
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    }

    private mutating func reconcileClock(now: Date) {
        if let lastDate, now < lastDate {
            samples.removeAll(keepingCapacity: true)
            lastValidDate.removeAll(keepingCapacity: true)
            interrupt()
        }
        lastDate = now
    }
}
