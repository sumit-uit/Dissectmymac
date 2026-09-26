import Foundation

public struct InstalledApp: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let bundleIdentifier: String?
    public let version: String?
    public let size: Int64
    /// Apps shipped with macOS (in /System/Applications or com.apple.*) can't be uninstalled.
    public var isSystemApp: Bool {
        url.path.hasPrefix("/System/") || (bundleIdentifier?.hasPrefix("com.apple.") ?? false)
    }

    public init(url: URL, name: String, bundleIdentifier: String?, version: String?, size: Int64) {
        self.url = url
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.size = size
    }
}

public enum AppCatalog {
    public static func defaultSearchPaths(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
        ]
    }

    /// Apps in the given folders (one level of sub-folders is searched too, e.g. /Applications/Adobe X/).
    public static func installedApps(in searchPaths: [URL] = defaultSearchPaths(), computeSizes: Bool = true) -> [InstalledApp] {
        var seen = Set<String>()
        var apps: [InstalledApp] = []
        let fm = FileManager.default

        func consider(_ url: URL) {
            guard url.pathExtension == "app", seen.insert(url.resolvingSymlinksInPath().path).inserted else { return }
            if let app = app(at: url, computeSize: computeSizes) { apps.append(app) }
        }

        for folder in searchPaths {
            let entries = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for entry in entries {
                if entry.pathExtension == "app" {
                    consider(entry)
                } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    let nested = (try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)) ?? []
                    nested.forEach(consider)
                }
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func app(at url: URL, computeSize: Bool = true) -> InstalledApp? {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApp(
            url: url,
            name: name,
            bundleIdentifier: bundle?.bundleIdentifier,
            version: info["CFBundleShortVersionString"] as? String,
            size: computeSize ? FileSize.allocatedSize(of: url) : 0
        )
    }
}
