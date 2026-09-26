import AppKit
import DissectCore
import SwiftUI

/// Explains where the disk space went, including the "System Data" and purgeable space Finder hides.
struct SpaceOverviewView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme
    @State private var usage = VolumeUsage.current()
    @State private var contributors: [HiddenSpaceItem] = []
    @State private var snapshots: [LocalSnapshot] = []
    @State private var isLoading = false
    @State private var snapshotMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Space Overview",
                              subtitle: "Where your space went, including the “System Data” macOS doesn't explain.") {
                    Button { load() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .disabled(isLoading)
                }
                if let usage { usageCard(usage).padding(.horizontal) }
                snapshotsCard.padding(.horizontal)
                GroupBox {
                    VStack(alignment: .leading, spacing: 0) {
                        if isLoading {
                            ProgressView("Measuring hidden space…").frame(maxWidth: .infinity).padding()
                        } else if contributors.isEmpty {
                            Text("Nothing significant found.").foregroundStyle(.secondary).padding()
                        }
                        ForEach(contributors) { item in
                            contributorRow(item)
                            if item != contributors.last { Divider() }
                        }
                    }
                } label: {
                    Label("What's inside “System Data”", systemImage: "questionmark.folder")
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
        }
        .task { if contributors.isEmpty { load() } }
    }

    private func usageCard(_ usage: VolumeUsage) -> some View {
        let free = usage.availableNow
        let purgeable = usage.purgeable
        let used = max(0, usage.total - free - purgeable)
        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        segment(width: geo.size.width, part: used, of: usage.total, color: theme.accent)
                        segment(width: geo.size.width, part: purgeable, of: usage.total, color: .orange)
                        segment(width: geo.size.width, part: free, of: usage.total, color: .gray.opacity(0.3))
                    }
                }
                .frame(height: 18)
                HStack(spacing: 18) {
                    legend("Used", used, theme.accent)
                    legend("Purgeable", purgeable, .orange)
                    legend("Free", free, .gray.opacity(0.5))
                    Spacer()
                    Text("Total \(ByteFormat.string(usage.total))").foregroundStyle(.secondary)
                }
                .font(.callout)
                if purgeable > 1_000_000_000 {
                    Text("\(ByteFormat.string(purgeable)) is purgeable: caches, iCloud files already uploaded, and snapshots that macOS deletes automatically when it needs room. Finder counts it as free; most other tools count it as used.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let tree = model.tree, model.scannedURL?.path == "/" {
                    let hidden = max(0, used - tree.size)
                    Text("Your last scan could see \(ByteFormat.string(tree.size)). \(ByteFormat.string(hidden)) is used by protected system files, snapshots or folders without permission.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Macintosh HD", systemImage: "internaldrive")
        }
    }

    private func segment(width: CGFloat, part: Int64, of total: Int64, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: total > 0 ? max(2, width * CGFloat(Double(part) / Double(total))) : 0)
    }

    private func legend(_ title: String, _ bytes: Int64, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text("\(title) \(ByteFormat.string(bytes))").monospacedDigit()
        }
    }

    private var snapshotsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if snapshots.isEmpty {
                    Text("No local Time Machine snapshots.").foregroundStyle(.secondary)
                } else {
                    Text("\(snapshots.count) local snapshot(s). While they exist, deleting files may not free space, because the snapshots still hold the old data. macOS removes them automatically after 24 hours or when space runs low.")
                        .font(.callout)
                    ForEach(snapshots.prefix(6)) { snapshot in
                        Text(snapshot.name).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Button("Thin Snapshots Now") {
                        let output = HiddenSpace.thinLocalSnapshots()
                        snapshotMessage = output == nil ? "macOS refused to thin snapshots (an administrator may be required)." : "Asked macOS to thin snapshots."
                        load()
                    }
                }
                if let snapshotMessage {
                    Text(snapshotMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Time Machine local snapshots", systemImage: "clock.arrow.circlepath")
        }
    }

    private func contributorRow(_ item: HiddenSpaceItem) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline)
                Text(item.explanation).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(ByteFormat.string(item.bytes)).monospacedDigit().font(.headline)
            switch item.action {
            case .junkCleaner:
                Button("Clean…") { model.selection = .junk }
            case .devCleaner:
                Button("Clean…") { model.selection = .devCleaner }
            case .reveal, .snapshots:
                Button("Show") { FinderActions.reveal(item.urls) }
            case .none:
                EmptyView()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    private func load() {
        isLoading = true
        usage = VolumeUsage.current()
        Task {
            let result = await Task.detached { (HiddenSpace.contributors(), HiddenSpace.localSnapshots()) }.value
            contributors = result.0
            snapshots = result.1
            isLoading = false
        }
    }
}
