import AppKit
import DissectCore
import SwiftUI

/// AppCleaner / Pearcleaner-style uninstaller: removes the app *and* its support files.
struct UninstallerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var apps: [InstalledApp] = []
    @State private var isLoading = false
    @State private var filter = ""
    @State private var selectedApp: InstalledApp?
    @State private var leftovers: [LeftoverItem] = []
    @State private var selectedLeftovers = Set<String>()
    @State private var includeApp = true
    @State private var isDropTargeted = false

    private var filteredApps: [InstalledApp] {
        let visible = apps.filter { !$0.isSystemApp }
        guard !filter.isEmpty else { return visible }
        return visible.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "App Uninstaller",
                          subtitle: "Remove apps completely, including caches, preferences and containers. Drop an app here.") {
                Button("Choose App…") { if let url = FinderActions.chooseApp() { select(url: url) } }
            }
            HSplitView {
                appList.frame(minWidth: 260, idealWidth: 300, maxWidth: 400, maxHeight: .infinity)
                detail.frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension == "app" }) else { return false }
            select(url: url)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(8)
            }
        }
        .task { if apps.isEmpty { await loadApps() } }
    }

    private var appList: some View {
        VStack(spacing: 0) {
            TextField("Filter apps", text: $filter).textFieldStyle(.roundedBorder).padding(8)
            if isLoading {
                ProgressView().frame(maxHeight: .infinity)
            } else {
                List(filteredApps, selection: Binding(get: { selectedApp?.id }, set: { id in
                    if let app = apps.first(where: { $0.id == id }) { select(app) }
                })) { app in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 28, height: 28)
                        VStack(alignment: .leading) {
                            Text(app.name)
                            Text(app.version.map { "Version \($0)" } ?? app.bundleIdentifier ?? "")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if app.size > 0 {
                            Text(ByteFormat.string(app.size)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .tag(app.id)
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let app = selectedApp {
            let isRunning = app.bundleIdentifier.map { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty } ?? false
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading) {
                        Text(app.name).font(.title2.bold())
                        Text(app.bundleIdentifier ?? "Unknown bundle identifier").foregroundStyle(.secondary)
                    }
                }
                .padding()
                if isRunning {
                    HStack {
                        Label("\(app.name) is running. Quit it before uninstalling.", systemImage: "exclamationmark.triangle")
                        Spacer()
                        Button("Quit \(app.name)") {
                            if let id = app.bundleIdentifier {
                                NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() }
                            }
                        }
                    }
                    .padding(10)
                    .background(.orange.opacity(0.12))
                }
                List {
                    Section("Application") {
                        Toggle(isOn: $includeApp) { FileRow(url: app.url, size: app.size) }
                    }
                    Section("Related files (\(leftovers.count))") {
                        if leftovers.isEmpty {
                            Text("No related files found.").foregroundStyle(.secondary)
                        }
                        ForEach(leftovers) { item in
                            Toggle(isOn: Binding(get: { selectedLeftovers.contains(item.id) },
                                                 set: { if $0 { selectedLeftovers.insert(item.id) } else { selectedLeftovers.remove(item.id) } })) {
                                FileRow(url: item.url, size: item.size, detail: item.location.title)
                            }
                        }
                    }
                }
                let chosen = leftovers.filter { selectedLeftovers.contains($0.id) }
                CleanBar(selectedCount: chosen.count + (includeApp ? 1 : 0),
                         selectedBytes: chosen.reduce(includeApp ? app.size : 0) { $0 + $1.size },
                         actionTitle: "Uninstall", feature: .uninstaller) {
                    var urls = chosen.map(\.url)
                    if includeApp { urls.insert(app.url, at: 0) }
                    model.report(Trash.moveToTrash(urls))
                    selectedApp = nil
                    leftovers = []
                    Task { await loadApps() }
                }
            }
        } else {
            ContentUnavailableView("Select an app", systemImage: "app.dashed",
                                   description: Text("Pick an app on the left, or drag one from Finder onto this window.")).frame(maxHeight: .infinity)
        }
    }

    private func loadApps() async {
        isLoading = apps.isEmpty
        // Show the list immediately, then fill in sizes (measuring every app bundle is slow).
        apps = await Task.detached { AppCatalog.installedApps(computeSizes: false) }.value
        isLoading = false
        let sized = await Task.detached { AppCatalog.installedApps(computeSizes: true) }.value
        apps = sized
        if let selected = selectedApp, let updated = sized.first(where: { $0.id == selected.id }) {
            selectedApp = updated
        }
    }

    private func select(url: URL) {
        if let app = apps.first(where: { $0.url == url }) ?? AppCatalog.app(at: url) { select(app) }
    }

    private func select(_ app: InstalledApp) {
        selectedApp = app
        includeApp = !app.isSystemApp
        leftovers = []
        if app.size == 0 {
            Task {
                let sized = await Task.detached { AppCatalog.app(at: app.url, computeSize: true) }.value
                if let sized, selectedApp?.id == sized.id { selectedApp = sized }
            }
        }
        Task {
            let found = await Task.detached { LeftoverScanner.leftovers(for: app) }.value
            guard selectedApp?.id == app.id else { return }
            leftovers = found
            selectedLeftovers = Set(found.map(\.id))
        }
    }
}
