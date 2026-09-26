#if os(macOS)
import Darwin
import Foundation

public struct ProcessSample: Identifiable, Sendable, Equatable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    /// CPU usage since the previous sample, where 1.0 = one full core.
    public let cpu: Double
    public let memory: UInt64
}

/// Top processes by CPU and memory (Activity Monitor style). Only processes the current user may inspect
/// are included; that covers every app the user runs.
public final class ProcessMonitor: @unchecked Sendable {
    private var previousCPUTime: [Int32: UInt64] = [:]
    private var previousSampleTime: UInt64 = 0
    private let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    public init() {}

    public func sample() -> [ProcessSample] {
        let capacity = max(1024, Int(proc_listallpids(nil, 0)) + 64)
        var pids = [Int32](repeating: 0, count: capacity)
        let byteCount = Int32(capacity * MemoryLayout<Int32>.stride)
        let count = Int(proc_listallpids(&pids, byteCount))
        guard count > 0 else { return [] }

        let now = mach_absolute_time()
        let elapsedNanos = previousSampleTime > 0 ? toNanos(now - previousSampleTime) : 0
        var cpuTimes: [Int32: UInt64] = [:]
        var samples: [ProcessSample] = []

        for pid in pids.prefix(min(count, capacity)) where pid > 0 {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.stride)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }
            let cpuTime = toNanos(info.pti_total_user + info.pti_total_system)
            cpuTimes[pid] = cpuTime
            var cpu = 0.0
            if elapsedNanos > 0, let previous = previousCPUTime[pid], cpuTime >= previous {
                cpu = Double(cpuTime - previous) / Double(elapsedNanos)
            }
            samples.append(ProcessSample(pid: pid, name: Self.name(of: pid), cpu: cpu, memory: info.pti_resident_size))
        }
        previousCPUTime = cpuTimes
        previousSampleTime = now
        return samples
    }

    private func toNanos(_ machTime: UInt64) -> UInt64 {
        machTime * UInt64(timebase.numer) / UInt64(max(1, timebase.denom))
    }

    static func name(of pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 1024)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        if length > 0 { return String(cString: buffer) }
        return "pid \(pid)"
    }
}
#endif
