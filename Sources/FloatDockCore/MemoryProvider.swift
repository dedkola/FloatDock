import Foundation
import Darwin

struct MemoryProvider {
    func read(at date: Date) -> MetricReading<MemoryValue> {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        guard status == KERN_SUCCESS, host_page_size(host, &pageSize) == KERN_SUCCESS,
              let value = MetricMath.memory(active: UInt64(info.active_count), inactive: UInt64(info.inactive_count),
                                            speculative: UInt64(info.speculative_count), wired: UInt64(info.wire_count),
                                            compressor: UInt64(info.compressor_page_count), purgeable: UInt64(info.purgeable_count),
                                            external: UInt64(info.external_page_count), pageSize: UInt64(pageSize),
                                            totalBytes: ProcessInfo.processInfo.physicalMemory, swapUsedBytes: swapUsed()) else {
            return .unavailable("Memory counters couldn't be read consistently.")
        }
        return .available(value, timestamp: date)
    }

    private func swapUsed() -> UInt64? {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0,
              size == MemoryLayout<xsw_usage>.size else { return nil }
        return swap.xsu_used
    }
}
