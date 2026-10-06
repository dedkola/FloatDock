import Foundation

/// One actor and one cancellable scheduler own all system reads. Nothing polls
/// from SwiftUI, and no timer or subprocess is created per metric.
public actor MetricsSampler {
    private var cpu = CPUProvider()
    private let memory = MemoryProvider()
    private let gpu = GPUProvider()
    private var network = NetworkProvider()
    private var cpuState = ReadingState<CPUValue>()
    private var memoryState = ReadingState<MemoryValue>()
    private var gpuState = ReadingState<GPUValue>()
    private var networkState = ReadingState<NetworkValue>()
    private var samplingTask: Task<Void, Never>?
    private var continuation: AsyncStream<SystemSnapshot>.Continuation?
    private var stream: AsyncStream<SystemSnapshot>?
    private var generation: UInt64 = 0
    private var stopped = false

    public init() {}

    /// Starts immediately, then reads at 1 Hz. Calling start while already active
    /// returns the existing stream; the intended consumer is one shared UI store.
    public func start() -> AsyncStream<SystemSnapshot> {
        if let stream { return stream }
        guard !stopped else { return AsyncStream { $0.finish() } }
        let pair = AsyncStream<SystemSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(2))
        continuation = pair.continuation
        stream = pair.stream
        generation &+= 1
        let currentGeneration = generation
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.terminate(generation: currentGeneration) }
        }
        samplingTask = Task { [weak self] in
            let clock = ContinuousClock()
            var next = clock.now
            while !Task.isCancelled {
                guard let self, await self.emit(generation: currentGeneration) else { break }
                next = next.advanced(by: .seconds(1))
                // A delayed cycle starts a new interval, rather than catching up
                // with a burst of near-zero elapsed counter reads.
                if next < clock.now { next = clock.now.advanced(by: .seconds(1)) }
                do { try await clock.sleep(until: next) } catch { break }
            }
        }
        return pair.stream
    }

    /// Used by the CLI diagnostics. Baselines are shared with the scheduler, so
    /// a probe must use its own sampler instance instead of extra UI polling.
    public func readOnce() -> SystemSnapshot {
        let date = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        let cpuReading = cpuState.accept(cpu.read(at: date, uptime: uptime))
        let memoryReading = memoryState.accept(memory.read(at: date))
        let gpuReading = gpuState.accept(gpu.read(at: date))
        let rawNetwork = network.read(at: date, uptime: uptime)
        if rawNetwork.unavailableReason == "Disconnected." { networkState.reset() }
        let networkReading = networkState.accept(rawNetwork)
        return SystemSnapshot(timestamp: date, cpu: cpuReading, memory: memoryReading, gpu: gpuReading, network: networkReading)
    }

    public func pause() {
        generation &+= 1
        samplingTask?.cancel()
        samplingTask = nil
        continuation?.finish()
        continuation = nil
        stream = nil
        cpu.reset()
        network.reset()
        cpuState.reset(); memoryState.reset(); gpuState.reset(); networkState.reset()
    }

    public func stop() {
        stopped = true
        pause()
    }

    private func emit(generation expected: UInt64) -> Bool {
        guard expected == generation, !stopped, continuation != nil else { return false }
        continuation?.yield(readOnce())
        return true
    }

    private func terminate(generation expected: UInt64) {
        guard expected == generation else { return }
        pause()
    }
}

/// A failed poll has no current value and adds no chart point. A recent previous
/// value may still appear in the tile for up to three seconds; the UI must check
/// this timestamp before choosing to display it.
struct ReadingState<Value: Sendable & Equatable> {
    private var last: (Value, Date)?

    mutating func reset() { last = nil }

    mutating func accept(_ reading: MetricReading<Value>) -> MetricReading<Value> {
        switch reading {
        case let .available(value, date):
            last = (value, date)
            return reading
        case .unavailable:
            if let (value, date) = last { return .stale(value, timestamp: date) }
            return reading
        case .warmingUp, .stale: return reading
        }
    }
}
