import AppKit
import Charts
import DissectCore
import SwiftUI

@MainActor
final class StatsModel: ObservableObject {
    struct Sample: Identifiable {
        let id = UUID()
        let time: Date
        let cpu: Double
        let memory: Double
    }

    @Published private(set) var cpu: Double = 0
    @Published private(set) var memory: MemoryStats?
    @Published private(set) var battery: BatteryStats?
    @Published private(set) var disk: DiskStats?
    @Published private(set) var download: Double = 0
    @Published private(set) var upload: Double = 0
    @Published private(set) var history: [Sample] = []
    @Published private(set) var thermal: ProcessInfo.ThermalState = .nominal
    @Published private(set) var topByCPU: [ProcessSample] = []
    @Published private(set) var topByMemory: [ProcessSample] = []

    private let monitor = SystemMonitor()
    private let processMonitor = ProcessMonitor()
    private var timer: Timer?
    private var subscribers = 0
    /// Process sampling is heavier, so it only runs while a view showing processes is open.
    private var processSubscribers = 0

    func startProcesses() {
        processSubscribers += 1
        if processSubscribers == 1 {
            // Prime the CPU counters so the next tick has a delta to compare against.
            _ = processMonitor.sample()
        }
        start()
    }

    func stopProcesses() {
        processSubscribers = max(0, processSubscribers - 1)
        stop()
    }

    func start() {
        subscribers += 1
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        subscribers = max(0, subscribers - 1)
        if subscribers == 0 {
            timer?.invalidate()
            timer = nil
        }
    }

    func refresh() {
        cpu = monitor.cpuLoad() ?? cpu
        memory = monitor.memory()
        battery = monitor.battery()
        disk = monitor.disk()
        if let net = monitor.networkThroughput() {
            download = net.down
            upload = net.up
        }
        thermal = monitor.thermalState
        if processSubscribers > 0 {
            let samples = processMonitor.sample()
            topByCPU = Array(samples.sorted { $0.cpu > $1.cpu }.prefix(8))
            topByMemory = Array(samples.sorted { $0.memory > $1.memory }.prefix(8))
        }
        history.append(Sample(time: Date(), cpu: cpu, memory: memory?.usedFraction ?? 0))
        if history.count > 90 { history.removeFirst(history.count - 90) }
    }
}

struct LiveStatsView: View {
    @EnvironmentObject private var stats: StatsModel
    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Live Monitor", subtitle: "CPU, memory, disk, network and battery, updated every 2 seconds.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    StatCard(title: "CPU", value: stats.cpu.formatted(.percent.precision(.fractionLength(0))),
                             fraction: stats.cpu, systemImage: "cpu")
                    if let memory = stats.memory {
                        StatCard(title: "Memory", value: "\(ByteFormat.string(memory.used)) of \(ByteFormat.string(memory.total))",
                                 fraction: memory.usedFraction, systemImage: "memorychip",
                                 detail: "Wired \(ByteFormat.string(memory.wired)) · Compressed \(ByteFormat.string(memory.compressed))")
                    }
                    if let disk = stats.disk {
                        StatCard(title: "Disk", value: "\(ByteFormat.string(disk.available)) free",
                                 fraction: disk.usedFraction, systemImage: "internaldrive",
                                 detail: "\(ByteFormat.string(disk.used)) used of \(ByteFormat.string(disk.total))")
                    }
                    StatCard(title: "Network", value: "↓ \(Self.rate(stats.download))  ↑ \(Self.rate(stats.upload))",
                             fraction: nil, systemImage: "network")
                    if let battery = stats.battery {
                        StatCard(title: "Battery", value: "\(battery.percent)%",
                                 fraction: Double(battery.percent) / 100, systemImage: battery.isCharging ? "battery.100.bolt" : "battery.75",
                                 detail: batteryDetail(battery))
                    }
                    StatCard(title: "Thermal State", value: Self.thermalTitle(stats.thermal), fraction: nil, systemImage: "thermometer.medium")
                }
                .padding(.horizontal)

                GroupBox("CPU & Memory (last 3 minutes)") {
                    Chart(stats.history) { sample in
                        LineMark(x: .value("Time", sample.time), y: .value("Load", sample.cpu), series: .value("Metric", "CPU"))
                            .foregroundStyle(by: .value("Metric", "CPU"))
                        LineMark(x: .value("Time", sample.time), y: .value("Load", sample.memory), series: .value("Metric", "Memory"))
                            .foregroundStyle(by: .value("Metric", "Memory"))
                    }
                    .chartYScale(domain: 0...1)
                    .chartYAxis { AxisMarks(format: FloatingPointFormatStyle<Double>.Percent()) }
                    .frame(height: 220)
                }
                .padding(.horizontal)

                HStack(alignment: .top, spacing: 16) {
                    ProcessList(title: "Top CPU", processes: stats.topByCPU) {
                        $0.cpu.formatted(.percent.precision(.fractionLength(0)))
                    }
                    ProcessList(title: "Top Memory", processes: stats.topByMemory) { ByteFormat.string($0.memory) }
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
        }
        .onAppear { stats.startProcesses() }
        .onDisappear { stats.stopProcesses() }
    }

    private func batteryDetail(_ battery: BatteryStats) -> String {
        var parts = [battery.isCharging ? "Charging" : (battery.isPluggedIn ? "Plugged in" : "On battery")]
        if let minutes = battery.minutesRemaining {
            parts.append("\(minutes / 60)h \(minutes % 60)m \(battery.isCharging ? "to full" : "left")")
        }
        return parts.joined(separator: " · ")
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        ByteFormat.string(Int64(bytesPerSecond)) + "/s"
    }

    static func thermalTitle(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Normal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let fraction: Double?
    let systemImage: String
    var detail: String?

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage).font(.headline)
            Text(value).font(.title3.monospacedDigit())
            if let fraction {
                SizeBar(fraction: fraction, color: fraction > 0.85 ? .red : (fraction > 0.65 ? .orange : theme.accent))
            }
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
    }
}

struct ProcessList: View {
    let title: String
    let processes: [ProcessSample]
    let value: (ProcessSample) -> String

    var body: some View {
        GroupBox(title) {
            VStack(spacing: 6) {
                if processes.isEmpty {
                    Text("Sampling…").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
                ForEach(processes) { process in
                    HStack {
                        Text(process.name).lineLimit(1)
                        Spacer()
                        Text(value(process)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button("Quit \(process.name)") { NSRunningApplication(processIdentifier: process.pid)?.terminate() }
                    }
                }
            }
            .padding(4)
        }
        .frame(maxWidth: .infinity)
    }
}

/// What the menu bar item shows next to its icon.
enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case icon, cpu, memory, cpuAndMemory, freeDisk
    var id: String { rawValue }
    var title: String {
        switch self {
        case .icon: return "Icon only"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .cpuAndMemory: return "CPU + Memory"
        case .freeDisk: return "Free disk space"
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var stats: StatsModel
    @AppStorage("menuBarDisplay") private var display = MenuBarDisplay.cpu.rawValue

    var body: some View {
        let cpu = stats.cpu.formatted(.percent.precision(.fractionLength(0)))
        let memory = stats.memory.map { $0.usedFraction.formatted(.percent.precision(.fractionLength(0))) } ?? "–"
        let disk = stats.disk.map { ByteFormat.string($0.available) } ?? "–"
        HStack(spacing: 4) {
            Image(systemName: "internaldrive")
            switch MenuBarDisplay(rawValue: display) ?? .cpu {
            case .icon: EmptyView()
            case .cpu: Text("CPU \(cpu)")
            case .memory: Text("MEM \(memory)")
            case .cpuAndMemory: Text("\(cpu) · \(memory)")
            case .freeDisk: Text(disk)
            }
        }
        .monospacedDigit()
        .onAppear { stats.start() }
    }
}

/// Compact monitor shown from the menu bar (Stats / iStat Menus style).
struct MenuBarStatsView: View {
    @EnvironmentObject private var stats: StatsModel
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DissectMyMac").font(.headline)
            row("CPU", stats.cpu.formatted(.percent.precision(.fractionLength(0))), stats.cpu)
            if let memory = stats.memory {
                row("Memory", ByteFormat.string(memory.used), memory.usedFraction)
            }
            if let disk = stats.disk {
                row("Disk", "\(ByteFormat.string(disk.available)) free", disk.usedFraction)
            }
            HStack {
                Text("Network")
                Spacer()
                Text("↓ \(LiveStatsView.rate(stats.download))  ↑ \(LiveStatsView.rate(stats.upload))").monospacedDigit()
            }
            if let battery = stats.battery {
                row("Battery", "\(battery.percent)%\(battery.isCharging ? " ⚡︎" : "")", Double(battery.percent) / 100)
            }
            if !stats.topByCPU.isEmpty {
                Divider()
                Text("Top processes").font(.caption).foregroundStyle(.secondary)
                ForEach(stats.topByCPU.prefix(5)) { process in
                    HStack {
                        Text(process.name).lineLimit(1)
                        Spacer()
                        Text(process.cpu.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
                    }
                    .font(.callout)
                }
            }
            Divider()
            HStack {
                Button("Open DissectMyMac") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 280)
        .onAppear { stats.startProcesses() }
        .onDisappear { stats.stopProcesses() }
    }

    private func row(_ title: String, _ value: String, _ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value).monospacedDigit()
            }
            SizeBar(fraction: fraction, color: theme.accent)
        }
    }
}
