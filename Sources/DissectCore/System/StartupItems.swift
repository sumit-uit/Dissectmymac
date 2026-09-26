import Foundation

/// A launchd job that starts at login or boot (the "Login Items & Extensions" that macOS hides).
public struct StartupItem: Identifiable, Hashable, Sendable {
    public enum Scope: String, Sendable { case userAgent = "User Agent", globalAgent = "Global Agent", daemon = "System Daemon" }

    public var id: String { plistURL.path }
    public let label: String
    public let plistURL: URL
    public let program: String?
    public let scope: Scope
    public let runAtLoad: Bool
    public let keepAlive: Bool
    /// Items in ~/Library/LaunchAgents can be removed without admin rights.
    public var isUserRemovable: Bool { scope == .userAgent }
    /// True when the executable the job points to no longer exists (a leftover from a deleted app).
    public let isBroken: Bool
}

public enum StartupItems {
    public static func all(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [StartupItem] {
        let sources: [(URL, StartupItem.Scope)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), .userAgent),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .globalAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .daemon),
        ]
        return sources.flatMap { folder, scope in
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return files.filter { $0.pathExtension == "plist" }.compactMap { parse($0, scope: scope) }
        }
        .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    static func parse(_ url: URL, scope: StartupItem.Scope) -> StartupItem? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        let label = plist["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
        let program = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first
        let keepAlive: Bool
        if let flag = plist["KeepAlive"] as? Bool {
            keepAlive = flag
        } else {
            keepAlive = plist["KeepAlive"] is [String: Any]
        }
        let broken = program.map { $0.hasPrefix("/") && !FileManager.default.fileExists(atPath: $0) } ?? false
        return StartupItem(label: label, plistURL: url, program: program, scope: scope,
                           runAtLoad: plist["RunAtLoad"] as? Bool ?? false, keepAlive: keepAlive, isBroken: broken)
    }
}
