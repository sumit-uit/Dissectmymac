import Foundation

/// A node in a scanned directory tree. Immutable after the scan finishes, except for `parent`.
public final class FileNode: Identifiable, Hashable, @unchecked Sendable {
    public let id = UUID()
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    /// Allocated size on disk in bytes (for directories, the sum of all descendants).
    public let size: Int64
    /// Number of regular files in this subtree (1 for a file).
    public let fileCount: Int
    public let modificationDate: Date?
    /// Children sorted by size, largest first.
    public let children: [FileNode]
    public private(set) weak var parent: FileNode?

    public init(
        url: URL,
        isDirectory: Bool,
        size: Int64,
        modificationDate: Date? = nil,
        children: [FileNode] = []
    ) {
        self.url = url
        self.name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        self.isDirectory = isDirectory
        self.modificationDate = modificationDate
        let sorted = children.sorted { $0.size > $1.size }
        self.children = sorted
        if isDirectory {
            self.size = sorted.reduce(size) { $0 + $1.size }
            self.fileCount = sorted.reduce(0) { $0 + $1.fileCount }
        } else {
            self.size = size
            self.fileCount = 1
        }
        for child in sorted { child.parent = self }
    }

    public var fileExtension: String { url.pathExtension.lowercased() }

    /// Path from the root down to this node.
    public var ancestry: [FileNode] {
        var chain: [FileNode] = [self]
        var current = parent
        while let node = current {
            chain.insert(node, at: 0)
            current = node.parent
        }
        return chain
    }

    /// Depth-first iteration over this node and every descendant.
    public func forEach(_ body: (FileNode) -> Void) {
        var stack: [FileNode] = [self]
        while let node = stack.popLast() {
            body(node)
            stack.append(contentsOf: node.children)
        }
    }

    public static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
