import AppKit
import DissectCore
import SwiftUI

struct JunkCleanerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var results: [JunkScanResult] = []
    @State private var selected = Set<String>()
    @State private var isScanning = false
    @State private var hasScanned = false

    private var selectedResults: [JunkScanResult] { results.filter { selected.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Junk Cleaner",
                          subtitle: "Caches, logs, developer leftovers, browser caches and old installers. Scanning is free.") {
                Button(hasScanned ? "Rescan" : "Scan for Junk") { scan() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isScanning)
            }
            if isScanning {
                ProgressView("Looking for junk…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasScanned {
                ContentUnavailableView("Find reclaimable space",
                                       systemImage: "sparkles",
                                       description: Text("Only files that apps or macOS recreate on demand are pre-selected.")).frame(maxHeight: .infinity)
            } else if results.isEmpty {
                ContentUnavailableView("Your Mac is clean", systemImage: "checkmark.circle").frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(JunkCategory.Group.allCases, id: \.self) { group in
                        let groupResults = results.filter { $0.category.group == group }
                        if !groupResults.isEmpty {
                            Section(group.rawValue) {
                                ForEach(groupResults) { result in
                                    JunkRow(result: result, isOn: binding(for: result.id))
                                }
                            }
                        }
                    }
                }
                CleanBar(selectedCount: selectedResults.reduce(0) { $0 + $1.items.count },
                         selectedBytes: selectedResults.reduce(0) { $0 + $1.bytes },
                         actionTitle: "Clean", feature: .junkCleaner) {
                    let urls = selectedResults.flatMap(\.items)
                    model.report(Trash.moveToTrash(urls))
                    scan()
                }
            }
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(get: { selected.contains(id) }, set: { if $0 { selected.insert(id) } else { selected.remove(id) } })
    }

    private func scan() {
        isScanning = true
        Task {
            let found = await Task.detached { JunkCleaner.scan(JunkCleaner.catalog()) }.value
            results = found
            selected = Set(found.filter { $0.category.recommended }.map(\.id))
            hasScanned = true
            isScanning = false
        }
    }
}

private struct JunkRow: View {
    let result: JunkScanResult
    @Binding var isOn: Bool
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(result.items.prefix(50), id: \.self) { url in
                Text(url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            if result.items.count > 50 {
                Text("and \(result.items.count - 50) more…").font(.caption).foregroundStyle(.tertiary)
            }
        } label: {
            HStack {
                Toggle("", isOn: $isOn).labelsHidden()
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.category.title)
                    Text(result.category.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(ByteFormat.string(result.bytes)).monospacedDigit()
            }
        }
    }
}
