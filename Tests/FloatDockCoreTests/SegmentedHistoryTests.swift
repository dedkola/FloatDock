import Foundation
import Testing
@testable import FloatDockCore

@Test func missingSingleTickBreaksOnlyTheAffectedSeries() throws {
    var history = SegmentedHistory()
    let origin = Date(timeIntervalSince1970: 1_000)
    history.append(kind: .cpu, value: 25, at: origin)
    history.append(kind: .memory, value: 1_000, at: origin)
    history.markMissing(kind: .cpu)
    history.append(kind: .memory, value: 1_010, at: origin.addingTimeInterval(1))
    history.append(kind: .cpu, value: 30, at: origin.addingTimeInterval(2))
    history.append(kind: .memory, value: 1_020, at: origin.addingTimeInterval(2))
    let cpu = history.samples.filter { $0.kind == .cpu }
    let memory = history.samples.filter { $0.kind == .memory }
    #expect(cpu.count == 2)
    #expect(cpu[0].segment != cpu[1].segment)
    #expect(memory.allSatisfy { $0.segment == memory[0].segment })
    #expect(cpu[1].date.timeIntervalSince(cpu[0].date) == 2)
}

@Test func rapidPauseBreaksEverySeriesEvenWithinOneSecond() {
    var history = SegmentedHistory()
    let origin = Date(timeIntervalSince1970: 1_000)
    for kind in MetricKind.allCases { history.append(kind: kind, value: 1, at: origin) }
    history.interrupt()
    for kind in MetricKind.allCases { history.append(kind: kind, value: 2, at: origin.addingTimeInterval(0.1)) }
    for kind in MetricKind.allCases {
        let values = history.samples.filter { $0.kind == kind }
        #expect(values.count == 2)
        #expect(values[0].segment != values[1].segment)
    }
}

@Test func segmentedHistoryPrunesElapsedTimeBoundsCapacityAndKeepsNetworkPairTogether() {
    var history = SegmentedHistory(duration: 60, capacity: 4)
    let origin = Date(timeIntervalSince1970: 1_000)
    #expect(history.samples.isEmpty)
    for offset in 0..<8 {
        history.append(kind: .network, value: Double(offset), secondary: Double(offset * 2),
                       at: origin.addingTimeInterval(Double(offset)))
    }
    #expect(history.samples.count == 4)
    #expect(history.samples.first?.value == 4)
    #expect(history.samples.last?.secondary == 14)
    history.prune(now: origin.addingTimeInterval(65))
    #expect(history.samples.count == 3)
    history.prune(now: origin.addingTimeInterval(120))
    #expect(history.samples.isEmpty)
}

@Test func clockMovingBackwardsStartsFreshHistory() {
    var history = SegmentedHistory()
    let origin = Date(timeIntervalSince1970: 1_000)
    history.append(kind: .gpu, value: 10, at: origin)
    history.append(kind: .gpu, value: 20, at: origin.addingTimeInterval(1))
    let previousSegment = history.samples.last?.segment
    history.append(kind: .gpu, value: 30, at: origin.addingTimeInterval(-10))
    #expect(history.samples.count == 1)
    #expect(history.samples.first?.date == origin.addingTimeInterval(-10))
    #expect(history.samples.first?.segment != previousSegment)
}

@Test func invalidSampleCreatesGapWithoutAnInventedPoint() {
    var history = SegmentedHistory()
    let origin = Date(timeIntervalSince1970: 1_000)
    history.append(kind: .network, value: 10, secondary: 1, at: origin)
    history.append(kind: .network, value: .nan, secondary: 2, at: origin.addingTimeInterval(1))
    history.append(kind: .network, value: 15, secondary: .infinity, at: origin.addingTimeInterval(2))
    history.append(kind: .network, value: 20, secondary: 5, at: origin.addingTimeInterval(3))
    #expect(history.samples.count == 2)
    #expect(history.samples[0].segment != history.samples[1].segment)
}

@Test func stalledSuccessfulProviderStillLeavesUnobservedTimeAsAGap() {
    var history = SegmentedHistory()
    let origin = Date(timeIntervalSince1970: 1_000)
    history.append(kind: .memory, value: 1_000, at: origin)
    history.append(kind: .gpu, value: 10, at: origin)
    history.append(kind: .memory, value: 1_010, at: origin.addingTimeInterval(1))
    // No failed poll is delivered while the sampler is stalled.
    history.append(kind: .memory, value: 1_020, at: origin.addingTimeInterval(5))
    history.append(kind: .gpu, value: 20, at: origin.addingTimeInterval(5))
    let memory = history.samples.filter { $0.kind == .memory }
    let gpu = history.samples.filter { $0.kind == .gpu }
    #expect(memory[0].segment == memory[1].segment)
    #expect(memory[1].segment != memory[2].segment)
    #expect(gpu[0].segment != gpu[1].segment)
}
