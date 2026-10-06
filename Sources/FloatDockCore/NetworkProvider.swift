import Foundation
import Darwin
import SystemConfiguration

struct NetworkProvider {
    private struct Interface {
        let name: String
        let label: String
    }

    private struct Counter {
        let interface: String
        let received: UInt64
        let sent: UInt64
        let uptime: TimeInterval
    }

    private var state = NetworkCounterState()

    mutating func reset() { state.reset() }

    mutating func read(at date: Date, uptime: TimeInterval) -> MetricReading<NetworkValue> {
        let interface: Interface
        switch primaryPhysicalInterface() {
        case let .success(value): interface = value
        case let .failure(reason):
            reset()
            return .unavailable(reason.rawValue)
        }
        guard let counter = byteCounters(interface: interface.name, uptime: uptime) else {
            reset()
            return .unavailable("Network counters are unavailable.")
        }
        return state.accept(interfaceName: interface.name, interfaceLabel: interface.label, received: counter.received,
                            sent: counter.sent, uptime: uptime, date: date)
    }

    private enum ResolutionFailure: String, Error {
        case disconnected = "Disconnected."
        case unavailable = "The primary physical network interface is unavailable."
    }

    private func primaryPhysicalInterface() -> Result<Interface, ResolutionFailure> {
        guard let store = SCDynamicStoreCreate(kCFAllocatorDefault, "FloatDock" as CFString, nil, nil),
              let preferences = SCPreferencesCreate(kCFAllocatorDefault, "FloatDock" as CFString, nil) else { return .failure(.unavailable) }
        var foundPrimary = false
        for family in ["IPv4", "IPv6"] {
            guard let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/\(family)" as CFString) as? [String: Any],
                  let serviceID = global[kSCDynamicStorePropNetPrimaryService as String] as? String else { continue }
            foundPrimary = true
            guard let service = SCNetworkServiceCopy(preferences, serviceID as CFString),
                  var current = SCNetworkServiceGetInterface(service) else { continue }
            // Resolve layered PPP/VPN service interfaces only when SC identifies the
            // real underlying physical interface. Never add outer and tunnel traffic.
            for _ in 0..<8 {
                let type = SCNetworkInterfaceGetInterfaceType(current) as String?
                if type == kSCNetworkInterfaceTypeEthernet as String || type == kSCNetworkInterfaceTypeIEEE80211 as String,
                   let bsd = SCNetworkInterfaceGetBSDName(current) as String?, isPhysicalName(bsd) {
                    let label = (SCNetworkServiceGetName(service) as String?)
                        ?? (SCNetworkInterfaceGetLocalizedDisplayName(current) as String?) ?? bsd
                    return .success(Interface(name: bsd, label: label))
                }
                guard let child = SCNetworkInterfaceGetInterface(current) else { break }
                current = child
            }
        }
        return .failure(foundPrimary ? .unavailable : .disconnected)
    }

    private func isPhysicalName(_ name: String) -> Bool {
        !["lo", "awdl", "llw", "utun", "tun", "ipsec", "gif", "stf", "bridge"].contains { name.hasPrefix($0) }
    }

    private func byteCounters(interface: String, uptime: TimeInterval) -> Counter? {
        let index = if_nametoindex(interface)
        guard index != 0 else { return nil }
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, Int32(index)]
        // The table may grow between sizing and copying; retry only that race.
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
            var bytes = [UInt8](repeating: 0, count: size)
            let status = bytes.withUnsafeMutableBytes { sysctl(&mib, u_int(mib.count), $0.baseAddress, &size, nil, 0) }
            if status != 0 { if errno == ENOMEM { continue }; return nil }
            return bytes.withUnsafeBytes { raw in
                var offset = 0
                while offset + 4 <= size {
                    let length = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                    guard length >= 4, offset + length <= size else { return nil }
                    let version = raw.load(fromByteOffset: offset + 2, as: UInt8.self)
                    let type = raw.load(fromByteOffset: offset + 3, as: UInt8.self)
                    if version == RTM_VERSION, type == RTM_IFINFO2, length >= MemoryLayout<if_msghdr2>.size {
                        let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                        if header.ifm_index == index {
                            guard header.ifm_flags & IFF_UP != 0, header.ifm_flags & IFF_RUNNING != 0 else { return nil }
                            return Counter(interface: interface, received: header.ifm_data.ifi_ibytes,
                                           sent: header.ifm_data.ifi_obytes, uptime: uptime)
                        }
                    }
                    offset += length
                }
                return nil
            }
        }
        return nil
    }
}

/// Keep baseline/session bookkeeping separate from the OS query so interface
/// changes, sleep, resets, and honest zero traffic can be tested deterministically.
struct NetworkCounterState {
    private var baseline: (name: String, received: UInt64, sent: UInt64, uptime: TimeInterval)?
    private var receivedSessionBytes: UInt64 = 0
    private var sentSessionBytes: UInt64 = 0

    mutating func reset() { baseline = nil }

    mutating func accept(interfaceName: String, interfaceLabel: String, received: UInt64, sent: UInt64, uptime: TimeInterval, date: Date) -> MetricReading<NetworkValue> {
        defer { baseline = (interfaceName, received, sent, uptime) }
        guard let previous = baseline, previous.name == interfaceName else { return .warmingUp }
        let elapsed = uptime - previous.uptime
        guard let receivedRate = MetricMath.rate(previous: previous.received, current: received, elapsed: elapsed),
              let sentRate = MetricMath.rate(previous: previous.sent, current: sent, elapsed: elapsed) else { return .warmingUp }
        let receiveSum = receivedSessionBytes.addingReportingOverflow(received - previous.received)
        let sendSum = sentSessionBytes.addingReportingOverflow(sent - previous.sent)
        receivedSessionBytes = receiveSum.overflow ? .max : receiveSum.partialValue
        sentSessionBytes = sendSum.overflow ? .max : sendSum.partialValue
        return .available(NetworkValue(receiveBytesPerSecond: receivedRate, sendBytesPerSecond: sentRate,
                                       interfaceName: interfaceName, interfaceLabel: interfaceLabel,
                                       receivedSessionBytes: receivedSessionBytes, sentSessionBytes: sentSessionBytes), timestamp: date)
    }
}
