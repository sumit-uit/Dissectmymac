import Foundation

/// Explains the space macOS lumps into "System Data" and the gap between what Finder shows and what's used.
public struct VolumeUsage: Sendable, Equatable {
    public let total: Int64
    /// Free space as Finder reports it (includes purgeable space macOS can reclaim on demand).
    public let availableForImportantUsage: Int64
    /// Truly free bytes right now.
    public let availableNow: Int64

    public var used: Int64 { max(0, total - availableNow) }
    /// Caches, iCloud-evictable files and snapshots macOS will delete automatically when space runs low.
    public var purgeable: Int64 { max(0, availableForImportantUsage - availableNow) }

    public init(total: Int64, availableForImportantUsage: Int64, availableNow: Int64) {
        self.total = total
        self.availableForImportantUsage = availableForImportantUsage
        self.availableNow = availableNow
    }

    public static func current(for volume: URL = URL(fileURLWithPath: "/")) -> VolumeUsage? {
        guard let values = try? volume.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ]), let total = values.volumeTotalCapacity else { return nil }
        let now = Int64(values.volumeAvailableCapacity ?? 0)
        return VolumeUsage(total: Int64(total),
                           availableForImportantUsage: values.volumeAvailableCapacityForImportantUsage ?? now,
                           availableNow: now)
    }
}

/// A well-known location that silently grows and shows up as "System Data".
public struct HiddenSpaceItem: Identifiable, Sendable, Hashable {
    public var id: String { title }
    public let title: String
    public let explanation: String
    public let urls: [URL]
    public let bytes: Int64
    /// Where the user should go to deal with it (a section of this app, or a hint).
    public let action: Action

    public enum Action: String, Sendable, Hashable {
        case junkCleaner, devCleaner, reveal, snapshots, none
    }
}

public struct LocalSnapshot: Identifiable, Sendable, Hashable {
    public var id: String { name }
    public let name: String
    /// The date component tmutil uses to delete it (e.g. "2026-09-26-101500").
    public let dateToken: String?
}

public enum HiddenSpace {
    /// Sizes the usual "System Data" culprits. Takes a few seconds; call off the main thread.
    public static func contributors(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [HiddenSpaceItem] {
        let lib = home.appendingPathComponent("Library")
        func l(_ p: String) -> URL { lib.appendingPathComponent(p) }
        func h(_ p: String) -> URL { home.appendingPathComponent(p) }

        let candidates: [(String, String, [URL], HiddenSpaceItem.Action)] = [
            ("App caches", "Temporary files apps rebuild automatically.", [l("Caches")], .junkCleaner),
            ("App data (Application Support)", "Databases, downloaded models, game data and offline content kept by apps.",
             [l("Application Support")], .reveal),
            ("Sandboxed app containers", "Data of App Store and sandboxed apps (Mail, Messages attachments, Photos caches…).",
             [l("Containers"), l("Group Containers")], .reveal),
            ("Messages attachments", "Photos and videos received in Messages.", [l("Messages/Attachments")], .reveal),
            ("Mail", "Downloaded mail and attachments.", [l("Mail")], .reveal),
            ("iPhone & iPad backups", "Local device backups made by Finder.", [l("Application Support/MobileSync/Backup")], .junkCleaner),
            ("Xcode & simulators", "DerivedData, device support files and simulator devices.",
             [l("Developer/Xcode"), l("Developer/CoreSimulator")], .devCleaner),
            ("Docker", "Docker's virtual disk image. Prune images with `docker system prune`.",
             [l("Containers/com.docker.docker/Data/vms"), h(".docker")], .reveal),
            ("Package manager caches", "npm, Homebrew, pip, Gradle and CocoaPods caches.",
             [h(".npm"), l("Caches/Homebrew"), h(".gradle"), l("Caches/CocoaPods"), h(".cache")], .junkCleaner),
            ("Logs", "App and system logs.", [l("Logs"), URL(fileURLWithPath: "/Library/Logs")], .junkCleaner),
            ("Virtual memory & sleep image", "Swap files and the hibernation image. macOS manages these; restart to shrink swap.",
             [URL(fileURLWithPath: "/private/var/vm")], .none),
            ("macOS installers & updates", "Downloaded system updates waiting to install.",
             [URL(fileURLWithPath: "/Library/Updates"), URL(fileURLWithPath: "/macOS Install Data")], .reveal),
        ]
        var items: [HiddenSpaceItem] = []
        for candidate in candidates {
            let existing = candidate.2.filter { FileManager.default.fileExists(atPath: $0.path) }
            let bytes = existing.reduce(Int64(0)) { $0 + FileSize.allocatedSize(of: $1) }
            guard bytes > 0 else { continue }
            items.append(HiddenSpaceItem(title: candidate.0, explanation: candidate.1, urls: existing,
                                         bytes: bytes, action: candidate.3))
        }
        return items.sorted { $0.bytes > $1.bytes }
    }

    // MARK: Time Machine local snapshots

    /// Local APFS snapshots made by Time Machine. They hold deleted files' blocks, so deleting big files
    /// often frees nothing until the snapshots expire.
    public static func localSnapshots() -> [LocalSnapshot] {
        guard let output = run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]) else { return [] }
        return parseSnapshots(output)
    }

    static func parseSnapshots(_ output: String) -> [LocalSnapshot] {
        output.split(separator: "\n").compactMap { line in
            let name = line.trimmingCharacters(in: .whitespaces)
            guard name.hasPrefix("com.apple.") else { return nil }
            // com.apple.TimeMachine.2026-09-26-101500.local
            let parts = name.split(separator: ".")
            let token = parts.first { $0.count == 17 && $0.filter { $0 == "-" }.count == 3 }.map(String.init)
            return LocalSnapshot(name: name, dateToken: token)
        }
    }

    /// Asks macOS to thin local snapshots as much as possible. Returns tmutil's output, or nil on failure.
    @discardableResult
    public static func thinLocalSnapshots() -> String? {
        run("/usr/bin/tmutil", ["thinlocalsnapshots", "/", "999999999999", "4"])
    }

    static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
