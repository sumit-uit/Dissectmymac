import AppKit
import DissectCore
import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = SearchQuery()
    @State private var minimumSizeMB = 0
    @State private var results: [FileNode] = []

    private let sizeOptions = [0, 1, 10, 100, 500, 1000]

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Power Search", subtitle: "Find anything in the scanned tree instantly. Supports * and ? wildcards.")
            if model.isScanning {
                ScanProgressView()
            } else if let tree = model.tree {
                HStack {
                    TextField("Search names, e.g. *.mov or invoice", text: $query.text)
                        .textFieldStyle(.roundedBorder)
                    Picker("Kind", selection: $query.kind) {
                        ForEach(SearchQuery.Kind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .frame(width: 140)
                    Picker("Type", selection: $query.category) {
                        Text("Any").tag(FileCategory?.none)
                        ForEach(FileCategory.allCases, id: \.self) { Text($0.title).tag(FileCategory?.some($0)) }
                    }
                    .frame(width: 220)
                    Picker("Larger than", selection: $minimumSizeMB) {
                        ForEach(sizeOptions, id: \.self) { Text($0 == 0 ? "Any size" : "\($0) MB").tag($0) }
                    }
                    .frame(width: 200)
                }
                .padding(.horizontal)
                List(results) { node in
                    FileRow(url: node.url, size: node.size)
                        .onTapGesture(count: 2) { FinderActions.reveal([node.url]) }
                }
                .overlay {
                    if results.isEmpty { ContentUnavailableView.search }
                }
                .task(id: SearchKey(query: query, minimumSizeMB: minimumSizeMB, treeID: tree.id)) {
                    var effective = query
                    effective.minimumSize = Int64(minimumSizeMB) * 1_000_000
                    try? await Task.sleep(for: .milliseconds(150)) // debounce typing
                    guard !Task.isCancelled else { return }
                    let finalQuery = effective
                    let found = await Task.detached { FileFinders.search(finalQuery, in: tree, limit: 2000) }.value
                    if !Task.isCancelled { results = found }
                }
            } else {
                NeedsScanView()
            }
        }
    }

    private struct SearchKey: Equatable {
        let query: SearchQuery
        let minimumSizeMB: Int
        let treeID: UUID
    }
}
