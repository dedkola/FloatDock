import Foundation

public enum MetricKind: String, CaseIterable, Sendable, Codable {
    case cpu, memory, gpu, network
}

/// Every provider keeps its own validity. A stale value is available to details,
/// but must never masquerade as a current tile value or a new chart point.
public enum MetricReading<Value: Sendable & Equatable>: Sendable, Equatable {
    case warmingUp
    case available(Value, timestamp: Date)
    case stale(Value, timestamp: Date)
    case unavailable(String)

    public var value: Value? {
        if case let .available(value, _) = self { return value }
        return nil
    }

    public var lastValue: Value? {
        switch self {
        case let .available(value, _), let .stale(value, _): return value
        default: return nil
        }
    }

    public var timestamp: Date? {
        switch self {
        case let .available(_, timestamp), let .stale(_, timestamp): return timestamp
        default: return nil
        }
    }

    public var unavailableReason: String? {
        if case let .unavailable(reason) = self { return reason }
        return nil
    }
}

public struct CPUValue: Sendable, Equatable {
    public let busyPercent: Double
    public let userPercent: Double
    public let systemPercent: Double
    public let idlePercent: Double

    public init(busyPercent: Double, userPercent: Double, systemPercent: Double, idlePercent: Double) {
        self.busyPercent = busyPercent
        self.userPercent = userPercent
        self.systemPercent = systemPercent
        self.idlePercent = idlePercent
    }
}

public struct MemoryValue: Sendable, Equatable {
    public let usedBytes: UInt64
    public let totalBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    public let swapUsedBytes: UInt64?
    public var usedPercent: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) * 100 }

    public init(usedBytes: UInt64, totalBytes: UInt64, wiredBytes: UInt64, compressedBytes: UInt64, swapUsedBytes: UInt64?) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.swapUsedBytes = swapUsedBytes
    }
}

public struct GPUValue: Sendable, Equatable {
    public let name: String
    public let utilizationPercent: Double

    public init(name: String, utilizationPercent: Double) {
        self.name = name
        self.utilizationPercent = utilizationPercent
    }
}

public struct NetworkValue: Sendable, Equatable {
    public let receiveBytesPerSecond: Double
    public let sendBytesPerSecond: Double
    public let interfaceName: String
    public let interfaceLabel: String
    public let receivedSessionBytes: UInt64
    public let sentSessionBytes: UInt64

    public init(receiveBytesPerSecond: Double, sendBytesPerSecond: Double, interfaceName: String, interfaceLabel: String, receivedSessionBytes: UInt64, sentSessionBytes: UInt64) {
        self.receiveBytesPerSecond = receiveBytesPerSecond
        self.sendBytesPerSecond = sendBytesPerSecond
        self.interfaceName = interfaceName
        self.interfaceLabel = interfaceLabel
        self.receivedSessionBytes = receivedSessionBytes
        self.sentSessionBytes = sentSessionBytes
    }
}

public struct SystemSnapshot: Sendable, Equatable {
    public let timestamp: Date
    public let cpu: MetricReading<CPUValue>
    public let memory: MetricReading<MemoryValue>
    public let gpu: MetricReading<GPUValue>
    public let network: MetricReading<NetworkValue>

    public init(timestamp: Date = Date(), cpu: MetricReading<CPUValue> = .warmingUp, memory: MetricReading<MemoryValue> = .warmingUp, gpu: MetricReading<GPUValue> = .warmingUp, network: MetricReading<NetworkValue> = .warmingUp) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.memory = memory
        self.gpu = gpu
        self.network = network
    }
}
