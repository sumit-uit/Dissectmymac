import AppKit
import Foundation
import UniformTypeIdentifiers

enum FinderActions {
    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func chooseFolder(prompt: String = "Scan") -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseApp() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: Full Disk Access

    /// Without Full Disk Access, macOS silently hides Mail, Safari, Messages and other protected folders,
    /// so scans under-report. We probe a TCC-protected file to find out.
    static var hasFullDiskAccess: Bool {
        let probes = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari/Bookmarks.plist").path,
        ]
        return probes.contains { FileHandle(forReadingAtPath: $0) != nil }
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
