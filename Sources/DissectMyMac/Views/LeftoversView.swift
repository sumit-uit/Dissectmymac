import AppKit
import DissectCore
import SwiftUI

/// Finds support files left behind by apps that were deleted by dragging them to the Trash.
struct LeftoversView: View {
    @EnvironmentObject private var model: AppModel
    @State private var items: [LeftoverItem] = []
    @State private var selected = Set<String>()
    @State private var isScanning = false
    @State private var hasScanned = false

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Leftover Cleanup",
                          subtitle: "Files in ~/Library that belong to apps you no longer have installed.") {
                Button(hasScanned ? "Rescan" : "Find Leftovers") { scan() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isScanning)
            }
            if isScanning {
                ProgressView("Comparing ~/Library with your installed apps…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasScanned {
                ContentUnavailableView("Find orphaned files", systemImage: "shippingbox",
                                       description: Text("Apple's own files and anything owned by an installed app are never listed."))
            } else if items.isEmpty {
                ContentUnavailableView("No leftovers found", systemImage: "checkmark.circle")
            } else {
                Text("Review before removing: an item can belong to a helper tool or an app installed outside /Applications.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                List {
                    ForEach(items) { item in
                        Toggle(isOn: Binding(get: { selected.contains(item.id) },
                                             set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } })) {
                            FileRow(url: item.url, size: item.size, detail: item.location.title)
                        }
                    }
                }
                let chosen = items.filter { selected.contains($0.id) }
                CleanBar(selectedCount: chosen.count, selectedBytes: chosen.reduce(0) { $0 + $1.size },
                         actionTitle: "Remove Leftovers", feature: .leftovers) {
                    model.report(Trash.moveToTrash(chosen.map(\.url)))
                    scan()
                }
            }
        }
    }

    private func scan() {
        isScanning = true
        Task {
            let found = await Task.detached {
                LeftoverScanner.orphans(installedApps: AppCatalog.installedApps(computeSizes: false))
            }.value
            items = found
            selected = []
            hasScanned = true
            isScanning = false
        }
    }
}
