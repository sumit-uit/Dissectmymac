import AppKit
import DissectCore
import SwiftUI

/// Gemini-style duplicate finder over the scanned tree (content-hash based, not name based).
struct DuplicatesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var groups: [DuplicateGroup] = []
    @State private var selected = Set<URL>()
    @State private var isRunning = false
    @State private var hasScanned = false
    @State private var minimumMB: Double = 1
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Duplicate Finder",
                          subtitle: "Byte-for-byte identical files in the scanned folder. Names don't matter.") {
                HStack {
                    Text("Min \(Int(minimumMB.rounded())) MB")
                    Slider(value: $minimumMB, in: 0...500).frame(width: 140)
                    Button(hasScanned ? "Rescan" : "Find Duplicates") { findDuplicates() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.tree == nil || isRunning)
                }
            }
            if model.isScanning {
                ScanProgressView()
            } else if model.tree == nil {
                NeedsScanView()
            } else if isRunning {
                VStack(spacing: 12) {
                    ProgressView("Comparing file contents…")
                    Button("Cancel") { task?.cancel() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasScanned {
                ContentUnavailableView("Find duplicate files", systemImage: "doc.on.doc",
                                       description: Text("Files are grouped by size, then compared with SHA-256 hashes."))
            } else if groups.isEmpty {
                ContentUnavailableView("No duplicates found", systemImage: "checkmark.circle")
            } else {
                HStack {
                    Text("\(groups.count) groups · \(ByteFormat.string(groups.reduce(0) { $0 + $1.wastedBytes })) reclaimable")
                    Spacer()
                    Button("Select All But Oldest") { autoSelect() }
                    Button("Deselect All") { selected = [] }
                }
                .padding(.horizontal)
                List {
                    ForEach(groups) { group in
                        Section("\(group.urls.count) copies · \(ByteFormat.string(group.fileSize)) each") {
                            ForEach(group.urls, id: \.self) { url in
                                Toggle(isOn: Binding(get: { selected.contains(url) },
                                                     set: { if $0 { selected.insert(url) } else { selected.remove(url) } })) {
                                    FileRow(url: url, size: group.fileSize)
                                }
                            }
                        }
                    }
                }
                let bytes = groups.reduce(Int64(0)) { total, group in
                    total + Int64(group.urls.filter { selected.contains($0) }.count) * group.fileSize
                }
                CleanBar(selectedCount: selected.count, selectedBytes: bytes,
                         actionTitle: "Remove Duplicates", feature: .duplicates) {
                    model.report(Trash.moveToTrash(Array(selected)))
                    let removed = selected
                    selected = []
                    groups = groups.compactMap { group in
                        let remaining = group.urls.filter { !removed.contains($0) }
                        return remaining.count > 1 ? DuplicateGroup(fileSize: group.fileSize, urls: remaining) : nil
                    }
                }
            }
        }
    }

    private func findDuplicates() {
        guard let tree = model.tree else { return }
        let minimum = Int64(max(1, minimumMB) * 1_000_000)
        isRunning = true
        task = Task.detached(priority: .userInitiated) {
            let result = try? DuplicateFinder.findDuplicates(in: tree, minimumSize: minimum)
            await MainActor.run { apply(result) }
        }
    }

    @MainActor
    private func apply(_ result: [DuplicateGroup]?) {
        isRunning = false
        guard let result else { return } // cancelled
        groups = result
        hasScanned = true
        autoSelect()
    }

    /// Keep the oldest copy (likely the original) in each group and select the rest.
    private func autoSelect() {
        var selection = Set<URL>()
        for group in groups {
            let dated = group.urls.map { url in
                (url, (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantFuture)
            }
            let keep = dated.min { $0.1 < $1.1 }?.0
            group.urls.filter { $0 != keep }.forEach { selection.insert($0) }
        }
        selected = selection
    }
}
