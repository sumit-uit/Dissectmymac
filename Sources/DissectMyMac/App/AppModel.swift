import AppKit
import DissectCore
import Foundation
import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case storage, spaceOverview, largeFiles, search, liveStats
    case junk, uninstaller, leftovers, duplicates, devCleaner, startup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .storage: return "Storage Map"
        case .spaceOverview: return "Space Overview"
        case .largeFiles: return "Large & Old Files"
        case .search: return "Power Search"
        case .liveStats: return "Live Monitor"
        case .junk: return "Junk Cleaner"
        case .uninstaller: return "App Uninstaller"
        case .leftovers: return "Leftover Cleanup"
        case .duplicates: return "Duplicate Finder"
        case .devCleaner: return "Developer Cleanup"
        case .startup: return "Startup Items"
        }
    }

    var systemImage: String {
        switch self {
        case .storage: return "square.grid.3x3.square"
        case .spaceOverview: return "chart.pie"
        case .largeFiles: return "doc.badge.clock"
        case .search: return "magnifyingglass"
        case .liveStats: return "gauge.with.dots.needle.33percent"
        case .junk: return "sparkles"
        case .uninstaller: return "trash.square"
        case .leftovers: return "shippingbox"
        case .duplicates: return "doc.on.doc"
        case .devCleaner: return "hammer"
        case .startup: return "power"
        }
    }

    /// The Pro feature needed to *clean* in this section (scanning is always free).
    var proFeature: ProFeature? {
        switch self {
        case .junk: return .junkCleaner
        case .uninstaller: return .uninstaller
        case .leftovers: return .leftovers
        case .duplicates: return .duplicates
        case .devCleaner: return .devCleaner
        case .startup: return .startupItems
        default: return nil
        }
    }

    static let analyze: [SidebarSection] = [.storage, .spaceOverview, .largeFiles, .search, .liveStats]
    static let clean: [SidebarSection] = [.junk, .uninstaller, .leftovers, .duplicates, .devCleaner, .startup]
}

/// Shared state for the disk scan, which several sections read.
@MainActor
final class AppModel: ObservableObject {
    @Published var selection: SidebarSection? = .storage
    @Published private(set) var tree: FileNode?
    @Published private(set) var scannedURL: URL?
    @Published private(set) var isScanning = false
    @Published private(set) var progress: ScanProgress?
    @Published var scanError: String?
    /// The folder currently shown in the storage map.
    @Published var focus: FileNode?
    /// DaisyDisk-style collector: items staged for removal.
    @Published var collected: [FileNode] = []
    @Published var notice: String?

    /// An app the user just dragged to the Trash; ContentView offers to clean its leftovers.
    @Published var trashedApp: InstalledApp?

    private var scanTask: Task<Void, Never>?
    private var trashWatcher: TrashWatcher?

    init() {
        let environment = ProcessInfo.processInfo.environment
        if let autoscan = environment["DMM_AUTOSCAN"] {
            // Used by UI tests and demos: "demo" builds a sample folder so screenshots are reproducible.
            let url = autoscan == "demo" ? DemoData.makeSampleFolder() : URL(fileURLWithPath: autoscan)
            scan(url)
        }
        switch environment["DMM_ONBOARDING"] {
        case "show": UserDefaults.standard.set(false, forKey: "didOnboard")
        case "skip": UserDefaults.standard.set(true, forKey: "didOnboard")
        default: break
        }
        let watchTrash = UserDefaults.standard.object(forKey: "watchTrash") == nil || UserDefaults.standard.bool(forKey: "watchTrash")
        if watchTrash, environment["DMM_UI_TEST"] == nil {
            setTrashWatching(true)
        }
    }

    // MARK: Trash watcher

    func setTrashWatching(_ enabled: Bool) {
        if enabled {
            guard trashWatcher == nil else { return }
            let watcher = TrashWatcher { app in
                Task { @MainActor [weak self] in self?.appWasTrashed(app) }
            }
            if watcher.start() { trashWatcher = watcher }
        } else {
            trashWatcher?.stop()
            trashWatcher = nil
        }
    }

    private func appWasTrashed(_ app: InstalledApp) {
        trashedApp = app
        Notifications.post(title: "\(app.name) moved to Trash",
                           body: "DissectMyMac found files it left behind. Click to review and remove them.")
    }

    func scan(_ url: URL) {
        scanTask?.cancel()
        isScanning = true
        progress = nil
        scanError = nil
        collected = []
        scannedURL = url
        selection = selection ?? .storage

        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let scanner = DiskScanner()
            do {
                let node = try scanner.scan(url) { progress in
                    Task { @MainActor in self?.progress = progress }
                }
                await MainActor.run {
                    self?.tree = node
                    self?.focus = node
                    self?.isScanning = false
                }
            } catch is CancellationError {
                await MainActor.run { self?.isScanning = false }
            } catch {
                await MainActor.run {
                    self?.isScanning = false
                    self?.scanError = error.localizedDescription
                }
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
    }

    func rescan() {
        if let scannedURL { scan(scannedURL) }
    }

    // MARK: Collector

    var collectedBytes: Int64 { collected.reduce(0) { $0 + $1.size } }

    func collect(_ node: FileNode) {
        guard !collected.contains(node) else { return }
        // Drop descendants already collected; skip if an ancestor is already collected.
        if collected.contains(where: { node.ancestry.contains($0) }) { return }
        collected.removeAll { $0.ancestry.contains(node) }
        collected.append(node)
    }

    func uncollect(_ node: FileNode) {
        collected.removeAll { $0 == node }
    }

    func trashCollected() {
        let sizes = Dictionary(collected.map { ($0.url, $0.size) }, uniquingKeysWith: { first, _ in first })
        let result = Trash.moveToTrash(collected.map(\.url), sizes: sizes)
        collected = []
        report(result)
        rescan()
    }

    func report(_ report: TrashReport) {
        var message = "Moved \(report.removed.count) item(s) to the Trash, freeing \(ByteFormat.string(report.bytesFreed))."
        if !report.failed.isEmpty {
            message += "\n\(report.failed.count) item(s) couldn't be removed: "
                + report.failed.prefix(3).map { "\($0.url.lastPathComponent) (\($0.message))" }.joined(separator: ", ")
        }
        notice = message
    }
}
