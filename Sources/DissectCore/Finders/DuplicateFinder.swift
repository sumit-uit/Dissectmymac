import CryptoKit
import Foundation

public struct DuplicateGroup: Identifiable, Sendable, Hashable {
    public let id = UUID()
    public let fileSize: Int64
    public let urls: [URL]

    /// Space recovered by keeping one copy and removing the rest.
    public var wastedBytes: Int64 { fileSize * Int64(max(0, urls.count - 1)) }
}

/// Finds byte-identical files in three passes (like Gemini / fdupes):
/// group by size → hash the first 64 KB → full SHA-256 of the remaining candidates.
public enum DuplicateFinder {
    static let partialHashBytes = 64 * 1024

    public static func findDuplicates(
        among files: [(url: URL, size: Int64)],
        minimumSize: Int64 = 1024,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> [DuplicateGroup] {
        let bySize = Dictionary(grouping: files.filter { $0.size >= minimumSize }, by: \.size)
            .filter { $0.value.count > 1 }
        let totalGroups = max(1, bySize.count)
        var processed = 0
        var groups: [DuplicateGroup] = []

        for (size, candidates) in bySize {
            if Task.isCancelled { throw CancellationError() }
            let byPartial = Dictionary(grouping: candidates.map(\.url)) { hash(of: $0, limit: partialHashBytes) }
            for (partial, urls) in byPartial where partial != nil && urls.count > 1 {
                let byFull: [String?: [URL]]
                if size <= Int64(partialHashBytes) {
                    byFull = [partial: urls]
                } else {
                    byFull = Dictionary(grouping: urls) { hash(of: $0, limit: nil) }
                }
                for (full, same) in byFull where full != nil && same.count > 1 {
                    groups.append(DuplicateGroup(fileSize: size, urls: same.sorted { $0.path < $1.path }))
                }
            }
            processed += 1
            progress?(Double(processed) / Double(totalGroups))
        }
        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    public static func findDuplicates(in root: FileNode, minimumSize: Int64 = 1024,
                                      progress: (@Sendable (Double) -> Void)? = nil) throws -> [DuplicateGroup] {
        var files: [(url: URL, size: Int64)] = []
        root.forEach { node in
            if !node.isDirectory { files.append((node.url, node.size)) }
        }
        return try findDuplicates(among: files, minimumSize: minimumSize, progress: progress)
    }

    /// SHA-256 of the first `limit` bytes (or the whole file when `limit` is nil).
    static func hash(of url: URL, limit: Int?) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        let chunkSize = 1 << 20
        while remaining > 0 {
            let data: Data?
            do {
                data = try handle.read(upToCount: min(chunkSize, remaining))
            } catch {
                return nil
            }
            guard let data, !data.isEmpty else { break }
            hasher.update(data: data)
            remaining -= data.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
