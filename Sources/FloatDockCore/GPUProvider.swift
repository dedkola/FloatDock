import Foundation
import IOKit
import Metal

struct GPUProvider {
    private let name: String

    init() { name = MTLCreateSystemDefaultDevice()?.name ?? "Apple GPU" }

    func read(at date: Date) -> MetricReading<GPUValue> {
        guard let matching = IOServiceMatching("IOAccelerator") else {
            return .unavailable("GPU activity isn't available on this Mac.")
        }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return .unavailable("GPU activity isn't available on this Mac.")
        }
        defer { IOObjectRelease(iterator) }
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            guard let property = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
                  let statistics = property as? [String: Any],
                  let percent = MetricMath.gpuPercent(statistics: statistics) else { continue }
            return .available(GPUValue(name: name, utilizationPercent: percent), timestamp: date)
        }
        return .unavailable("GPU activity isn't available on this Mac.")
    }
}
