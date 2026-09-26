import Foundation

public struct TrashReport: Sendable {
    public var removed: [URL] = []
    public var failed: [(url: URL, message: String)] = []
    public var bytesFreed: Int64 = 0
}

/// Every removal in the app goes through here. Items are moved to the Trash (recoverable),
/// never deleted outright — except items that are already in the Trash, which are deleted
/// when emptying it.
public enum Trash {
    public static func moveToTrash(_ urls: [URL], sizes: [URL: Int64] = [:]) -> TrashReport {
        var report = TrashReport()
        let fm = FileManager.default
        let trashPath = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path
        for url in urls {
            guard SafetyPolicy.isRemovable(url) else {
                report.failed.append((url, "Protected location"))
                continue
            }
            let size = sizes[url] ?? FileSize.allocatedSize(of: url)
            do {
                if url.path.hasPrefix(trashPath + "/") {
                    try fm.removeItem(at: url)
                } else {
                    try fm.trashItem(at: url, resultingItemURL: nil)
                }
                report.removed.append(url)
                report.bytesFreed += size
            } catch {
                report.failed.append((url, error.localizedDescription))
            }
        }
        return report
    }
}

/// Guard rails so a bug or a bad selection can never remove something critical.
public enum SafetyPolicy {
    static let protectedExact: Set<String> = [
        "/", "/System", "/Library", "/Applications", "/Users", "/usr", "/bin", "/sbin", "/private", "/etc", "/var",
        "/opt", "/Volumes", "/cores",
    ]

    public static func isRemovable(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let path = url.standardizedFileURL.path
        if protectedExact.contains(path) { return false }
        if path.hasPrefix("/System/") || path.hasPrefix("/usr/") || path.hasPrefix("/bin/") || path.hasPrefix("/sbin/") {
            return false
        }
        let homePath = home.standardizedFileURL.path
        let protectedHome = ["", "/Library", "/Desktop", "/Documents", "/Downloads", "/Pictures", "/Movies", "/Music",
                             "/Applications", "/Library/Caches", "/Library/Application Support", "/Library/Preferences",
                             "/Library/Containers", "/Library/Logs", "/.Trash"]
        if protectedHome.contains(where: { path == homePath + $0 }) { return false }
        return true
    }
}
