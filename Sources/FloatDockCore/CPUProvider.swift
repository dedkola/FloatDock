import Foundation
import Darwin

struct CPUProvider {
    private var baseline: (ticks: CPUTicks, uptime: TimeInterval)?

    mutating func reset() { baseline = nil }

    mutating func read(at date: Date, uptime: TimeInterval) -> MetricReading<CPUValue> {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else {
            reset()
            return .unavailable("CPU counters couldn't be read.")
        }
        let ticks = CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1,
                             idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
        defer { baseline = (ticks, uptime) }
        guard let previous = baseline, uptime > previous.uptime, uptime - previous.uptime <= 3 else { return .warmingUp }
        guard let value = MetricMath.cpu(previous: previous.ticks, current: ticks) else {
            return .unavailable("CPU counters are being refreshed.")
        }
        return .available(value, timestamp: date)
    }
}
