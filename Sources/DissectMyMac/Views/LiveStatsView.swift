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

    private let monitor = SystemMonitor()
    private var timer: Timer?
    private var subscribers = 0

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
            }
            .padding(.bottom)
        }
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
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
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
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
