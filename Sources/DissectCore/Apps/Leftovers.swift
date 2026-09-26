import Foundation

/// A file or folder in ~/Library (or /Library) that belongs to an app.
public struct LeftoverItem: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let location: LibraryLocation
    public let size: Int64
}

public struct LibraryLocation: Hashable, Sendable {
    public let title: String
    public let url: URL
    /// Whether entries here may be matched by the app's display name as well as its bundle ID.
    /// (Application Support/Caches/Logs often use "AppName"; Preferences/Containers always use bundle IDs.)
    public let matchesByName: Bool

    public init(title: String, url: URL, matchesByName: Bool) {
        self.title = title
        self.url = url
        self.matchesByName = matchesByName
    }

    public static func userLocations(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [LibraryLocation] {
        let lib = home.appendingPathComponent("Library")
        func loc(_ path: String, _ byName: Bool) -> LibraryLocation {
            LibraryLocation(title: path, url: lib.appendingPathComponent(path), matchesByName: byName)
        }
        return [
            loc("Application Support", true),
            loc("Caches", true),
            loc("Preferences", false),
            loc("Preferences/ByHost", false),
            loc("Containers", false),
            loc("Group Containers", false),
            loc("Saved Application State", false),
            loc("Logs", true),
            loc("HTTPStorages", false),
            loc("WebKit", false),
            loc("Cookies", false),
            loc("LaunchAgents", false),
            loc("Application Scripts", false),
            loc("Autosave Information", false),
        ]
    }

    public static func systemLocations() -> [LibraryLocation] {
        let lib = URL(fileURLWithPath: "/Library")
        return [
            LibraryLocation(title: "/Library/Application Support", url: lib.appendingPathComponent("Application Support"), matchesByName: true),
            LibraryLocation(title: "/Library/Caches", url: lib.appendingPathComponent("Caches"), matchesByName: false),
            LibraryLocation(title: "/Library/Preferences", url: lib.appendingPathComponent("Preferences"), matchesByName: false),
            LibraryLocation(title: "/Library/LaunchAgents", url: lib.appendingPathComponent("LaunchAgents"), matchesByName: false),
            LibraryLocation(title: "/Library/LaunchDaemons", url: lib.appendingPathComponent("LaunchDaemons"), matchesByName: false),
            LibraryLocation(title: "/Library/PrivilegedHelperTools", url: lib.appendingPathComponent("PrivilegedHelperTools"), matchesByName: false),
        ]
    }
}

/// Pure matching rules, separated out so they can be unit-tested.
public enum LeftoverMatcher {
    static let strippedSuffixes = [".plist", ".savedState", ".binarycookies", ".sfl2", ".sfl3", ".lockfile"]

    /// "com.foo.Bar.plist" → "com.foo.Bar"; "ABCDE12345.com.foo.Bar" → "com.foo.Bar";
    /// "com.foo.Bar.ABCD-1234-....plist" (ByHost) → "com.foo.Bar.ABCD-1234-..."
    public static func normalizedIdentifier(_ entryName: String) -> String {
        var name = entryName
        for suffix in strippedSuffixes where name.hasSuffix(suffix) {
            name.removeLast(suffix.count)
        }
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        if parts.count == 2, isTeamIdentifier(parts[0]) { name = parts[1] }
        return name
    }

    static func isTeamIdentifier(_ s: String) -> Bool {
        s.count == 10 && s.allSatisfy { $0.isUppercase || $0.isNumber }
    }

    public static func matches(entryName: String, bundleID: String?, appName: String?, allowNameMatch: Bool) -> Bool {
        let normalized = normalizedIdentifier(entryName).lowercased()
        if let bundleID, !bundleID.isEmpty {
            let id = bundleID.lowercased()
            if normalized == id || normalized.hasPrefix(id + ".") { return true }
            // Group containers: "group.com.foo.bar" / "TEAMID.group.com.foo".
            if normalized == "group." + id || normalized.hasPrefix("group." + id + ".") { return true }
        }
        if allowNameMatch, let appName, appName.count >= 3 {
            let name = appName.lowercased()
            let entry = entryName.lowercased()
            if entry == name || entry == name.replacingOccurrences(of: " ", with: "") { return true }
        }
        return false
    }

    /// True for entries that look like reverse-DNS app identifiers (com.vendor.app).
    public static func looksLikeBundleIdentifier(_ entryName: String) -> Bool {
        let normalized = normalizedIdentifier(entryName)
        let parts = normalized.split(separator: ".")
        guard parts.count >= 3 else { return false }
        let tld = parts[0].lowercased()
        return ["com", "org", "net", "io", "de", "co", "app", "dev", "me", "ru", "jp", "cn", "uk", "fr", "us", "info", "group"]
            .contains(tld)
    }

    /// Identifiers that belong to macOS itself and should never be flagged as orphans.
    public static func isProtected(_ identifier: String) -> Bool {
        let id = identifier.lowercased()
        let prefixes = ["com.apple.", "group.com.apple.", "apple.", "com.microsoft.autoupdate"]
        return prefixes.contains { id.hasPrefix($0) } || id.hasPrefix("systemgroup.")
    }

    /// Whether `identifier` is owned by any installed app (exact, child, or parent identifier match).
    public static func isOwned(_ identifier: String, byAnyOf bundleIDs: Set<String>) -> Bool {
        let id = identifier.lowercased()
        let groupStripped = id.hasPrefix("group.") ? String(id.dropFirst(6)) : id
        for candidate in [id, groupStripped] {
            if bundleIDs.contains(candidate) { return true }
            // Walk up: com.foo.bar.helper → com.foo.bar → com.foo
            var parts = candidate.split(separator: ".")
            while parts.count > 2 {
                parts.removeLast()
                if bundleIDs.contains(parts.joined(separator: ".")) { return true }
            }
        }
        // Child identifiers: an installed "com.foo.bar.helper" owns "com.foo.bar" data too.
        return bundleIDs.contains { $0.hasPrefix(groupStripped + ".") }
    }
}

/// Finds an app's support files (AppCleaner/Pearcleaner-style) and orphaned files from deleted apps.
public enum LeftoverScanner {
    public static func leftovers(
        for app: InstalledApp,
        locations: [LibraryLocation] = LibraryLocation.userLocations() + LibraryLocation.systemLocations()
    ) -> [LeftoverItem] {
        var items: [LeftoverItem] = []
        let fm = FileManager.default
        for location in locations {
            let entries = (try? fm.contentsOfDirectory(atPath: location.url.path)) ?? []
            for entry in entries where LeftoverMatcher.matches(
                entryName: entry, bundleID: app.bundleIdentifier, appName: app.name, allowNameMatch: location.matchesByName
            ) {
                let url = location.url.appendingPathComponent(entry)
                items.append(LeftoverItem(url: url, location: location, size: FileSize.allocatedSize(of: url)))
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    /// Items in ~/Library whose bundle-ID-style name doesn't belong to any installed app.
    /// These are *candidates* only — always let the user review before removing.
    public static func orphans(
        installedApps: [InstalledApp],
        locations: [LibraryLocation] = LibraryLocation.userLocations()
    ) -> [LeftoverItem] {
        let bundleIDs = Set(installedApps.compactMap { $0.bundleIdentifier?.lowercased() })
        var items: [LeftoverItem] = []
        let fm = FileManager.default
        for location in locations {
            let entries = (try? fm.contentsOfDirectory(atPath: location.url.path)) ?? []
            for entry in entries where LeftoverMatcher.looksLikeBundleIdentifier(entry) {
                let identifier = LeftoverMatcher.normalizedIdentifier(entry)
                if LeftoverMatcher.isProtected(identifier) || LeftoverMatcher.isOwned(identifier, byAnyOf: bundleIDs) {
                    continue
                }
                let url = location.url.appendingPathComponent(entry)
                items.append(LeftoverItem(url: url, location: location, size: FileSize.allocatedSize(of: url)))
            }
        }
        return items.sorted { $0.size > $1.size }
    }
}
