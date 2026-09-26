import AppKit
import DissectCore
import SwiftUI

/// Finds regenerable build and dependency folders (node_modules, Pods, target, .build, venv, …) in code projects.
struct DevCleanerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var roots: [URL] = [FileManager.default.homeDirectoryForCurrentUser]
    @State private var artifacts: [ProjectArtifact] = []
    @State private var selected = Set<String>()
    @State private var isScanning = false
    @State private var hasScanned = false
    @State private var olderThanDays = 30

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Developer Cleanup",
                          subtitle: "node_modules, Pods, build folders and virtualenvs that can be regenerated with one command.") {
                HStack {
                    Menu("Folders (\(roots.count))") {
                        ForEach(roots, id: \.self) { root in
                            Button("Remove \(root.path)") { roots.removeAll { $0 == root } }
                        }
                        Divider()
                        Button("Add Folder…") { if let url = FinderActions.chooseFolder(prompt: "Add") { roots.append(url) } }
                    }
                    .frame(width: 130)
                    Button(hasScanned ? "Rescan" : "Scan Projects") { scan() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isScanning || roots.isEmpty)
                }
            }
            if isScanning {
                ProgressView("Searching for project build folders…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasScanned {
                ContentUnavailableView("Reclaim space from old projects", systemImage: "hammer",
                                       description: Text("Build folders are only matched when the project file (package.json, Cargo.toml, Podfile…) is next to them."))
            } else if artifacts.isEmpty {
                ContentUnavailableView("No build folders found", systemImage: "checkmark.circle")
            } else {
                HStack {
                    Picker("Select untouched for", selection: $olderThanDays) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("1 year").tag(365)
                    }
                    .frame(width: 260)
                    Button("Select") { selectStale() }
                    Spacer()
                }
                .padding(.horizontal)
                List {
                    ForEach(artifacts) { artifact in
                        Toggle(isOn: Binding(get: { selected.contains(artifact.id) },
                                             set: { if $0 { selected.insert(artifact.id) } else { selected.remove(artifact.id) } })) {
                            FileRow(url: artifact.url, size: artifact.size,
                                    detail: "\(artifact.kind) · \(artifact.projectURL.path)\(age(artifact))")
                        }
                    }
                }
                let chosen = artifacts.filter { selected.contains($0.id) }
                CleanBar(selectedCount: chosen.count, selectedBytes: chosen.reduce(0) { $0 + $1.size },
                         actionTitle: "Remove Build Folders", feature: .devCleaner) {
                    model.report(Trash.moveToTrash(chosen.map(\.url)))
                    artifacts.removeAll { selected.contains($0.id) }
                    selected = []
                }
            }
        }
    }

    private func age(_ artifact: ProjectArtifact) -> String {
        guard let date = artifact.lastModified else { return "" }
        return " · modified \(date.formatted(.relative(presentation: .named)))"
    }

    private func selectStale() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -olderThanDays, to: Date()) ?? Date()
        selected = Set(artifacts.filter { ($0.lastModified ?? .distantPast) < cutoff }.map(\.id))
    }

    private func scan() {
        isScanning = true
        let roots = self.roots
        Task {
            let found = await Task.detached { (try? DevProjectScanner.scan(roots: roots)) ?? [] }.value
            artifacts = found
            hasScanned = true
            isScanning = false
            selectStale()
        }
    }
}
