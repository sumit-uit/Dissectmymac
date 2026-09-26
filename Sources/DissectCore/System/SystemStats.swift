#if os(macOS)
import Darwin
import Foundation
import IOKit.ps

public struct MemoryStats: Sendable, Equatable {
    public let total: UInt64
    public let used: UInt64
    public let wired: UInt64
    public let compressed: UInt64
    public let cached: UInt64
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

public struct BatteryStats: Sendable, Equatable {
    public let percent: Int
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let minutesRemaining: Int?
}

public struct DiskStats: Sendable, Equatable {
    public let total: Int64
    public let available: Int64
    public var used: Int64 { max(0, total - available) }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

public struct NetworkCounters: Sendable, Equatable {
    public let bytesIn: UInt64
    public let bytesOut: UInt64
}

/// Live system metrics (iStat Menus / Stats style). All reads are cheap and safe to poll every second.
public final class SystemMonitor: @unchecked Sendable {
    private var previousCPU: (busy: UInt64, total: UInt64)?
    private var previousNetwork: (counters: NetworkCounters, time: Date)?

    public init() {}

    /// Overall CPU load 0…1 since the previous call (first call returns load since boot).
    public func cpuLoad() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle
        defer { previousCPU = (busy, total) }
        if let previous = previousCPU, total > previous.total {
            return Double(busy - previous.busy) / Double(total - previous.total)
        }
        return total > 0 ? Double(busy) / Double(total) : 0
    }

    public func memory() -> MemoryStats? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = UInt64(pageSize)
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        // "App memory" as Activity Monitor reports it.
        let internalBytes = UInt64(stats.internal_page_count) * page
        let purgeable = UInt64(stats.purgeable_count) * page
        let appMemory = internalBytes > purgeable ? internalBytes - purgeable : 0
        let cached = (UInt64(stats.external_page_count) + UInt64(stats.purgeable_count)) * page
        return MemoryStats(
            total: ProcessInfo.processInfo.physicalMemory,
            used: appMemory + wired + compressed,
            wired: wired,
            compressed: compressed,
            cached: cached
        )
    }

    public func battery() -> BatteryStats? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let unmanaged = IOPSGetPowerSourceDescription(snapshot, source),
                  let info = unmanaged.takeUnretainedValue() as? [String: Any],
                  (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = info[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = info[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let charging = info[kIOPSIsChargingKey] as? Bool ?? false
            let pluggedIn = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let minutesKey = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let minutes = (info[minutesKey] as? Int).flatMap { $0 > 0 ? $0 : nil }
            return BatteryStats(percent: current * 100 / maximum, isCharging: charging,
                                isPluggedIn: pluggedIn, minutesRemaining: minutes)
        }
        return nil
    }

    public func disk(for volume: URL = URL(fileURLWithPath: "/")) -> DiskStats? {
        guard let values = try? volume.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        ]), let total = values.volumeTotalCapacity else { return nil }
        let available = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
        return DiskStats(total: Int64(total), available: available)
    }

    /// Download / upload speed in bytes per second since the previous call.
    public func networkThroughput() -> (down: Double, up: Double)? {
        guard let counters = Self.networkCounters() else { return nil }
        let now = Date()
        defer { previousNetwork = (counters, now) }
        guard let previous = previousNetwork else { return (0, 0) }
        let elapsed = now.timeIntervalSince(previous.time)
        guard elapsed > 0 else { return (0, 0) }
        let down = counters.bytesIn >= previous.counters.bytesIn ? counters.bytesIn - previous.counters.bytesIn : 0
        let up = counters.bytesOut >= previous.counters.bytesOut ? counters.bytesOut - previous.counters.bytesOut : 0
        return (Double(down) / elapsed, Double(up) / elapsed)
    }

    static func networkCounters() -> NetworkCounters? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = cursor {
            let entry = pointer.pointee
            if let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
               let data = entry.ifa_data, !String(cString: entry.ifa_name).hasPrefix("lo") {
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                bytesIn += UInt64(stats.ifi_ibytes)
                bytesOut += UInt64(stats.ifi_obytes)
            }
            cursor = entry.ifa_next
        }
        return NetworkCounters(bytesIn: bytesIn, bytesOut: bytesOut)
    }

    public var thermalState: ProcessInfo.ThermalState { ProcessInfo.processInfo.thermalState }
    public var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }
}
#endif
