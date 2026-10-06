import Foundation
import Testing
@testable import FloatDockCore


@Test func cpuNormalizesAllCoresAndIncludesNiceWithUser() throws {
    let previous = CPUTicks(user: 100, system: 100, idle: 100, nice: 100)
    let current = CPUTicks(user: 120, system: 110, idle: 165, nice: 105)
    let value = try #require(MetricMath.cpu(previous: previous, current: current))
    #expect(abs(value.busyPercent - 35) < 0.0001)
    #expect(abs(value.userPercent - 25) < 0.0001)
    #expect(abs(value.systemPercent + value.userPercent + value.idlePercent - 100) < 0.0001)
}

@Test func cpuZeroDeltaAndResetAreUnknown() {
    let ticks = CPUTicks(user: 100, system: 100, idle: 100, nice: 0)
    #expect(MetricMath.cpu(previous: ticks, current: ticks) == nil)
    #expect(MetricMath.cpu(previous: ticks, current: CPUTicks(user: 2, system: 2, idle: 2, nice: 0)) == nil)
}

@Test func cpuCounterRolloverIsMeasuredDeliberately() throws {
    let previous = CPUTicks(user: .max - 5, system: 100, idle: 100, nice: 0)
    let current = CPUTicks(user: 4, system: 105, idle: 105, nice: 0)
    let value = try #require(MetricMath.cpu(previous: previous, current: current))
    #expect(value.busyPercent == 75)
    #expect(MetricMath.tickDelta(.max - 5, 4) == 10)
    #expect(MetricMath.tickDelta(1_000, 1) == nil)
}

@Test func memoryUsesRuntimePageSizeAndDoesNotAddCompressionTwice() throws {
    let value = try #require(MetricMath.memory(active: 10, inactive: 3, speculative: 2, wired: 4,
                                               compressor: 5, purgeable: 2, external: 6,
                                               pageSize: 16_384, totalBytes: 1_048_576, swapUsedBytes: nil))
    #expect(value.usedBytes == 16 * 16_384)
    #expect(value.wiredBytes == 4 * 16_384)
    #expect(value.compressedBytes == 5 * 16_384)
    #expect(value.usedPercent == 25)
    #expect(value.swapUsedBytes == nil)
}

@Test func inconsistentMemoryDoesNotUnderflowClampOrOverflow() {
    #expect(MetricMath.memory(active: 1, inactive: 0, speculative: 0, wired: 0, compressor: 0,
                             purgeable: 2, external: 0, pageSize: 16_384, totalBytes: 32_768, swapUsedBytes: 0) == nil)
    #expect(MetricMath.memory(active: .max, inactive: .max, speculative: 0, wired: 0, compressor: 0,
                             purgeable: 0, external: 0, pageSize: 16_384, totalBytes: .max, swapUsedBytes: 0) == nil)
    #expect(MetricMath.memory(active: 3, inactive: 0, speculative: 0, wired: 0, compressor: 0,
                             purgeable: 0, external: 0, pageSize: 16_384, totalBytes: 32_768, swapUsedBytes: 0) == nil)
}

@Test func networkRateUsesElapsedTimeAndDistinguishesZeroFromInvalid() {
    #expect(MetricMath.rate(previous: 100, current: 1_100, elapsed: 2) == 500)
    #expect(MetricMath.rate(previous: 100, current: 100, elapsed: 1) == 0)
    #expect(MetricMath.rate(previous: 100, current: 99, elapsed: 1) == nil)
    #expect(MetricMath.rate(previous: 100, current: 200, elapsed: 0) == nil)
    #expect(MetricMath.rate(previous: 100, current: 200, elapsed: .nan) == nil)
    #expect(MetricMath.rate(previous: 100, current: 200, elapsed: 60) == nil)
}

@Test func networkInterfaceSwitchAndPausePreserveOnlyMeasuredSessionTraffic() throws {
    var state = NetworkCounterState()
    let date = Date(timeIntervalSince1970: 1_000)
    #expect(state.accept(interfaceName: "en0", interfaceLabel: "Wi-Fi", received: 100, sent: 50, uptime: 1, date: date) == .warmingUp)
    let sample = try #require(state.accept(interfaceName: "en0", interfaceLabel: "Wi-Fi", received: 200, sent: 75, uptime: 2, date: date).value)
    #expect(sample.receivedSessionBytes == 100)
    #expect(sample.sentSessionBytes == 25)
    #expect(state.accept(interfaceName: "en5", interfaceLabel: "Ethernet", received: 9_000_000, sent: 3_000, uptime: 3, date: date) == .warmingUp)
    let switched = try #require(state.accept(interfaceName: "en5", interfaceLabel: "Ethernet", received: 9_000_200, sent: 3_100, uptime: 4, date: date).value)
    #expect(switched.receivedSessionBytes == 300)
    state.reset()
    #expect(state.accept(interfaceName: "en5", interfaceLabel: "Ethernet", received: 10_000_000, sent: 30_000, uptime: 100, date: date) == .warmingUp)
    let resumed = try #require(state.accept(interfaceName: "en5", interfaceLabel: "Ethernet", received: 10_000_000, sent: 30_000, uptime: 101, date: date).value)
    #expect(resumed.receiveBytesPerSecond == 0)
    #expect(resumed.receivedSessionBytes == 300)
    #expect(resumed.sentSessionBytes == 125)
}

@Test func networkCounterResetRebaselinesInsteadOfProducingASpike() throws {
    var state = NetworkCounterState()
    let date = Date()
    _ = state.accept(interfaceName: "en0", interfaceLabel: "Wi-Fi", received: 20_000, sent: 2_000, uptime: 1, date: date)
    #expect(state.accept(interfaceName: "en0", interfaceLabel: "Wi-Fi", received: 0, sent: 0, uptime: 2, date: date) == .warmingUp)
    let value = try #require(state.accept(interfaceName: "en0", interfaceLabel: "Wi-Fi", received: 20, sent: 10, uptime: 3, date: date).value)
    #expect(value.receiveBytesPerSecond == 20)
    #expect(value.receivedSessionBytes == 20)
}

@Test func gpuAcceptsRealZeroAndRejectsUnsupportedOrInvalidFields() {
    #expect(MetricMath.gpuPercent(statistics: ["Device Utilization %": 0]) == 0)
    #expect(MetricMath.gpuPercent(statistics: ["Device Utilization %": 55.5]) == 55.5)
    #expect(MetricMath.gpuPercent(statistics: ["Device Utilization %": true]) == nil)
    #expect(MetricMath.gpuPercent(statistics: ["Device Utilization %": "25"]) == nil)
    #expect(MetricMath.gpuPercent(statistics: ["Device Utilization %": Double.nan]) == nil)
    #expect(MetricMath.gpuPercent(statistics: ["Device Utilization %": 101]) == nil)
    #expect(MetricMath.gpuPercent(statistics: ["GPU Activity(%)": 0.5]) == nil)
    #expect(MetricMath.gpuPercent(statistics: [:]) == nil)
}

@Test func staleReadingsRetainTimestampWithoutBecomingChartSamples() {
    var state = ReadingState<GPUValue>()
    let date = Date(timeIntervalSince1970: 1_000)
    let value = GPUValue(name: "Test GPU", utilizationPercent: 10)
    _ = state.accept(.available(value, timestamp: date))
    let stale = state.accept(.unavailable("Missing field"))
    #expect(stale.value == nil)
    #expect(stale.lastValue == value)
    #expect(stale.timestamp == date)
    state.reset()
    #expect(state.accept(.unavailable("Missing field")) == .unavailable("Missing field"))
}

@Test func historyKeepsRealTimeGapsAndIsBoundedAtStartupAndAfterSleep() {
    var history = HistoryBuffer(capacity: 3, duration: 60)
    let origin = Date(timeIntervalSince1970: 1_000)
    #expect(history.points.isEmpty)
    history.append(HistoryPoint(timestamp: origin, value: 1))
    history.append(HistoryPoint(timestamp: origin.addingTimeInterval(1), value: nil))
    history.append(HistoryPoint(timestamp: origin.addingTimeInterval(2), value: 2))
    #expect(history.points[1].value == nil)
    history.append(HistoryPoint(timestamp: origin.addingTimeInterval(3), value: 3))
    #expect(history.points.count == 3)
    #expect(history.points.first?.timestamp == origin.addingTimeInterval(1))
    history.append(HistoryPoint(timestamp: origin.addingTimeInterval(120), value: 4))
    #expect(history.points.count == 1)
    #expect(history.points.first?.timestamp == origin.addingTimeInterval(120))
}
