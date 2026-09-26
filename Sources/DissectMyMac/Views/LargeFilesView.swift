import AppKit
import DissectCore
import SwiftUI

struct LargeFilesView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case largest = "Largest"
        case old = "Not Modified in a Year"
        var id: String { rawValue }
    }

    @EnvironmentObject private var model: AppModel
    @State private var mode: Mode = .largest
    @State private var minimumMB: Double = 100
    @State private var selection = Set<FileNode.ID>()

    private var files: [FileNode] {
        guard let tree = model.tree else { return [] }
        let minimum = Int64(minimumMB * 1_000_000)
        switch mode {
        case .largest:
            return FileFinders.largestFiles(in: tree, limit: 500, minimumSize: minimum)
        case .old:
            let yearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
            return FileFinders.oldFiles(in: tree, notModifiedSince: yearAgo, minimumSize: minimum)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Large & Old Files",
                          subtitle: "The biggest single files, and big files you haven't touched in a year.") {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }
            if model.isScanning {
                ScanProgressView()
            } else if model.tree == nil {
                NeedsScanView()
            } else {
                let files = self.files
                HStack {
                    Text("Minimum size: \(Int(minimumMB)) MB")
                    Slider(value: $minimumMB, in: 10...2000, step: 10).frame(width: 240)
                    Spacer()
                    Text("\(files.count) files · \(ByteFormat.string(files.reduce(0) { $0 + $1.size }))")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                Table(files, selection: $selection) {
                    TableColumn("Name") { file in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path)).resizable().frame(width: 16, height: 16)
                            Text(file.name)
                        }
                    }
                    TableColumn("Size") { Text(ByteFormat.string($0.size)).monospacedDigit() }.width(90)
                    TableColumn("Modified") { file in
                        Text(file.modificationDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
                    }
                    .width(110)
                    TableColumn("Location") { Text($0.url.deletingLastPathComponent().path).foregroundStyle(.secondary) }
                }
                .contextMenu(forSelectionType: FileNode.ID.self) { ids in
                    let urls = files.filter { ids.contains($0.id) }.map(\.url)
                    Button("Reveal in Finder") { FinderActions.reveal(urls) }
                    Button("Add to Collector") {
                        for file in files where ids.contains(file.id) { model.collect(file) }
                    }
                } primaryAction: { ids in
                    FinderActions.reveal(files.filter { ids.contains($0.id) }.map(\.url))
                }
                let selected = files.filter { selection.contains($0.id) }
                CleanBar(selectedCount: selected.count, selectedBytes: selected.reduce(0) { $0 + $1.size },
                         actionTitle: "Move to Trash") {
                    model.report(Trash.moveToTrash(selected.map(\.url)))
                    selection = []
                    model.rescan()
                }
            }
        }
    }
}
