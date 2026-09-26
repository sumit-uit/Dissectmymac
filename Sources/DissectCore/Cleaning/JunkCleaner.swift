import Foundation

/// A category of safely-removable files (CleanMyMac / DevCleaner style).
public struct JunkCategory: Identifiable, Hashable, Sendable {
    public enum Group: String, CaseIterable, Sendable {
        case system = "System Junk"
        case developer = "Developer Junk"
        case browsers = "Browser Caches"
        case trash = "Trash"
        case downloads = "Downloads & Installers"
    }

    public let id: String
    public let title: String
    public let detail: String
    public let group: Group
    /// Folders whose *contents* are removed (the folder itself is kept).
    public let paths: [URL]
    /// Only items matching one of these extensions are included (empty = everything).
    public let extensions: Set<String>
    /// Recommended categories are pre-selected; others are opt-in.
    public let recommended: Bool

    public init(id: String, title: String, detail: String, group: Group, paths: [URL],
                extensions: Set<String> = [], recommended: Bool = true) {
        self.id = id
        self.title = title
        self.detail = detail
        self.group = group
        self.paths = paths
        self.extensions = extensions
        self.recommended = recommended
    }
}

public struct JunkScanResult: Identifiable, Sendable {
    public var id: String { category.id }
    public let category: JunkCategory
    public let items: [URL]
    public let bytes: Int64
}

public enum JunkCleaner {
    public static func catalog(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [JunkCategory] {
        let lib = home.appendingPathComponent("Library")
        func h(_ path: String) -> URL { home.appendingPathComponent(path) }
        func l(_ path: String) -> URL { lib.appendingPathComponent(path) }

        return [
            // System
            JunkCategory(id: "user-caches", title: "User Cache Files",
                         detail: "Temporary caches apps rebuild automatically.",
                         group: .system, paths: [l("Caches")]),
            JunkCategory(id: "user-logs", title: "User Logs", detail: "Diagnostic and app log files.",
                         group: .system, paths: [l("Logs")]),
            JunkCategory(id: "crash-reports", title: "Crash Reports",
                         detail: "Old diagnostic reports.",
                         group: .system, paths: [l("Logs/DiagnosticReports")]),
            JunkCategory(id: "ios-updates", title: "iOS / iPadOS Software Updates",
                         detail: "Downloaded .ipsw firmware files.",
                         group: .system, paths: [l("iTunes/iPhone Software Updates"), l("iTunes/iPad Software Updates")]),
            JunkCategory(id: "ios-backups", title: "iPhone & iPad Backups",
                         detail: "Local device backups. Review carefully — these may be your only backup.",
                         group: .system, paths: [l("Application Support/MobileSync/Backup")], recommended: false),
            JunkCategory(id: "mail-downloads", title: "Mail Attachments",
                         detail: "Attachments opened from Mail (they remain in your mailbox).",
                         group: .system, paths: [l("Containers/com.apple.mail/Data/Library/Mail Downloads")],
                         recommended: false),

            // Developer
            JunkCategory(id: "xcode-derived", title: "Xcode DerivedData", detail: "Build intermediates; rebuilt on next build.",
                         group: .developer, paths: [l("Developer/Xcode/DerivedData")]),
            JunkCategory(id: "xcode-archives", title: "Xcode Archives", detail: "Old app archives (needed to symbolicate old releases).",
                         group: .developer, paths: [l("Developer/Xcode/Archives")], recommended: false),
            JunkCategory(id: "xcode-device-support", title: "Xcode Device Support",
                         detail: "Debug symbols for devices; re-downloaded when a device connects.",
                         group: .developer,
                         paths: [l("Developer/Xcode/iOS DeviceSupport"), l("Developer/Xcode/watchOS DeviceSupport"),
                                 l("Developer/Xcode/tvOS DeviceSupport"), l("Developer/Xcode/visionOS DeviceSupport")]),
            JunkCategory(id: "simulator-caches", title: "Simulator Caches", detail: "CoreSimulator caches.",
                         group: .developer, paths: [l("Developer/CoreSimulator/Caches")]),
            JunkCategory(id: "package-caches", title: "Package Manager Caches",
                         detail: "npm, Yarn, pnpm, pip, Homebrew, CocoaPods, Gradle, Carthage and SwiftPM caches.",
                         group: .developer,
                         paths: [h(".npm/_cacache"), l("Caches/Yarn"), l("Caches/pnpm"), l("Caches/pip"),
                                 l("Caches/Homebrew"), l("Caches/CocoaPods"), h(".gradle/caches"),
                                 l("Caches/org.carthage.CarthageKit"), l("Caches/org.swift.swiftpm"),
                                 h(".cache/pip"), h(".cache/yarn")]),

            // Browsers
            JunkCategory(id: "browser-caches", title: "Browser Caches",
                         detail: "Safari, Chrome, Firefox, Edge, Brave and Arc caches. History and passwords are untouched.",
                         group: .browsers,
                         paths: [l("Caches/com.apple.Safari"), l("Caches/Google/Chrome"), l("Caches/Firefox/Profiles"),
                                 l("Caches/Microsoft Edge"), l("Caches/BraveSoftware"), l("Caches/company.thebrowser.Browser")]),

            // Trash
            JunkCategory(id: "trash", title: "Trash", detail: "Items already in your Trash.",
                         group: .trash, paths: [h(".Trash")]),

            // Downloads
            JunkCategory(id: "installers", title: "Installers in Downloads",
                         detail: ".dmg, .pkg and .zip files you've probably already installed.",
                         group: .downloads, paths: [h("Downloads")],
                         extensions: ["dmg", "pkg", "mpkg", "iso", "xip"], recommended: false),
        ]
    }

    public static func scan(_ categories: [JunkCategory]) -> [JunkScanResult] {
        let fm = FileManager.default
        return categories.compactMap { category in
            var items: [URL] = []
            var bytes: Int64 = 0
            for folder in category.paths {
                let entries = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
                for entry in entries {
                    if entry.lastPathComponent == ".DS_Store" { continue }
                    if !category.extensions.isEmpty, !category.extensions.contains(entry.pathExtension.lowercased()) { continue }
                    let size = FileSize.allocatedSize(of: entry)
                    items.append(entry)
                    bytes += size
                }
            }
            return items.isEmpty ? nil : JunkScanResult(category: category, items: items, bytes: bytes)
        }
    }
}
