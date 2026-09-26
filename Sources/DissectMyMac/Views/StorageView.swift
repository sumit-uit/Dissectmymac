import AppKit
import DissectCore
import SwiftUI

/// The DissectMac / DaisyDisk-style interactive storage map with a collector for staging deletions.
struct StorageView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme
    @State private var hovered: FileNode?
    @State private var confirmingTrash = false

    var body: some View {
        Group {
            if model.isScanning {
                ScanProgressView()
            } else if let focus = model.focus ?? model.tree {
                content(focus)
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.3x3.square").font(.system(size: 56)).foregroundStyle(theme.accent)
            Text("See what's taking up space").font(.title.bold())
            Text("Scan a folder or your whole Mac. Everything is analyzed locally; nothing leaves your computer.")
                .foregroundStyle(.secondary)
            ScanButtons()
            if let error = model.scanError {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            if let disk = SystemMonitor().disk() {
                VStack(alignment: .leading) {
                    Text("Macintosh HD: \(ByteFormat.string(disk.used)) used of \(ByteFormat.string(disk.total))")
                        .font(.callout)
                    SizeBar(fraction: disk.usedFraction, color: theme.accent)
                }
                .frame(width: 360)
                .padding(.top)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(_ focus: FileNode) -> some View {
        HSplitView {
            VStack(spacing: 0) {
                breadcrumb(focus)
                TreemapView(node: focus, hovered: $hovered) { node in
                    if node.isDirectory, !node.children.isEmpty { model.focus = node }
                } onCollect: { node in
                    model.collect(node)
                }
                .padding(8)
                statusBar(focus)
            }
            .frame(minWidth: 500)

            sidePanel(focus)
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
        }
    }

    private func breadcrumb(_ focus: FileNode) -> some View {
        HStack(spacing: 4) {
            Button {
                if let parent = focus.parent { model.focus = parent }
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(focus.parent == nil)
            .help("Up one level")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(focus.ancestry) { node in
                        Button(node.name) { model.focus = node }
                            .buttonStyle(.borderless)
                            .fontWeight(node == focus ? .semibold : .regular)
                        if node != focus {
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            Spacer()
            Button { model.rescan() } label: { Image(systemName: "arrow.clockwise") }.help("Rescan")
            Button("Scan…") { if let url = FinderActions.chooseFolder() { model.scan(url) } }
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }

    private func statusBar(_ focus: FileNode) -> some View {
        HStack {
            if let hovered {
                Image(nsImage: NSWorkspace.shared.icon(forFile: hovered.url.path)).resizable().frame(width: 16, height: 16)
                Text(hovered.url.path).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(ByteFormat.string(hovered.size)).monospacedDigit()
            } else {
                Text("\(focus.name) · \(ByteFormat.string(focus.size)) · \(focus.fileCount.formatted()) files")
                Spacer()
                Text("Click a folder to open it · Right-click to collect").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func sidePanel(_ focus: FileNode) -> some View {
        VStack(spacing: 0) {
            List {
                Section("Contents") {
                    ForEach(focus.children.prefix(200)) { child in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Image(systemName: child.isDirectory ? "folder.fill" : "doc")
                                        .foregroundStyle(child.isDirectory ? theme.accent : .secondary)
                                    Text(child.name).lineLimit(1)
                                    Spacer()
                                    Text(ByteFormat.string(child.size)).monospacedDigit().foregroundStyle(.secondary)
                                }
                                SizeBar(fraction: focus.size > 0 ? Double(child.size) / Double(focus.size) : 0, color: theme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { if child.isDirectory { model.focus = child } }
                        .onHover { inside in hovered = inside ? child : nil }
                        .contextMenu { nodeMenu(child) }
                        .draggable(child.url)
                    }
                }
                Section("By Type") {
                    ForEach(FileFinders.categoryBreakdown(of: focus).prefix(8)) { entry in
                        HStack {
                            Circle().fill(theme.color(for: entry.category)).frame(width: 8, height: 8)
                            Text(entry.category.title)
                            Spacer()
                            Text(ByteFormat.string(entry.bytes)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
            collector
        }
    }

    @ViewBuilder
    private func nodeMenu(_ node: FileNode) -> some View {
        Button("Add to Collector") { model.collect(node) }
        Button("Reveal in Finder") { FinderActions.reveal([node.url]) }
        if node.isDirectory { Button("Open in Map") { model.focus = node } }
    }

    private var collector: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Collector", systemImage: "tray.full")
                    .font(.headline)
                Spacer()
                if !model.collected.isEmpty {
                    Button("Clear") { model.collected = [] }.buttonStyle(.borderless)
                }
            }
            if model.collected.isEmpty {
                Text("Drag items here or right-click → Add to Collector.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.collected) { node in
                            HStack {
                                Text(node.name).lineLimit(1)
                                Spacer()
                                Text(ByteFormat.string(node.size)).monospacedDigit().foregroundStyle(.secondary)
                                Button { model.uncollect(node) } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.borderless)
                            }
                            .font(.callout)
                        }
                    }
                }
                .frame(maxHeight: 120)
                Button(role: .destructive) {
                    confirmingTrash = true
                } label: {
                    Label("Move \(ByteFormat.string(model.collectedBytes)) to Trash", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.bar)
        .dropDestination(for: URL.self) { urls, _ in
            guard let tree = model.tree else { return false }
            var added = false
            tree.forEach { node in
                if urls.contains(node.url) { model.collect(node); added = true }
            }
            return added
        }
        .confirmationDialog("Move collected items to Trash?", isPresented: $confirmingTrash) {
            Button("Move to Trash", role: .destructive) { model.trashCollected() }
        } message: {
            Text("\(model.collected.count) item(s), \(ByteFormat.string(model.collectedBytes)). You can restore them from the Trash.")
        }
    }
}
