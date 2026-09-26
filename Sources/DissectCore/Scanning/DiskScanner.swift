import Foundation

public struct ScanProgress: Sendable, Equatable {
    public let filesScanned: Int
    public let bytesScanned: Int64
    public let currentPath: String
}

/// Builds a `FileNode` tree for a folder or volume.
///
/// `scan` is synchronous and checks `Task.isCancelled`, so run it inside a task you own
/// (e.g. `Task.detached`) and cancel that task to stop the scan.
public final class DiskScanner: @unchecked Sendable {
    public struct Options: Sendable {
        /// Don't descend into other mounted volumes (like `du -x`).
        public var stayOnVolume = true
        public var includeHidden = true
        /// Treat app bundles and other packages as single opaque items.
        public var collapsePackages = false
        /// Paths that are never scanned (e.g. /System/Volumes, which mirrors the data volume).
        public var excludedPaths: Set<String> = ["/System/Volumes", "/Volumes", "/dev", "/private/var/vm"]

        public init() {}
    }

    public let options: Options
    private let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey, .volumeIdentifierKey, .contentModificationDateKey,
    ]
    private let progressInterval = 1000

    private var filesScanned = 0
    private var bytesScanned: Int64 = 0
    private var rootVolume: NSObject?
    private var progressHandler: (@Sendable (ScanProgress) -> Void)?

    public init(options: Options = Options()) {
        self.options = options
    }

    public func scan(_ root: URL, progress: (@Sendable (ScanProgress) -> Void)? = nil) throws -> FileNode {
        filesScanned = 0
        bytesScanned = 0
        progressHandler = progress
        let values = try root.resourceValues(forKeys: Set(resourceKeys))
        rootVolume = values.volumeIdentifier as? NSObject
        let node = try makeNode(root, values: values, isRoot: true)
        progress?(ScanProgress(filesScanned: filesScanned, bytesScanned: bytesScanned, currentPath: root.path))
        return node
    }

    private func makeNode(_ url: URL, values: URLResourceValues, isRoot: Bool = false) throws -> FileNode {
        let isDirectory = values.isDirectory == true && values.isSymbolicLink != true
        let descend = isDirectory && (isRoot || !(options.collapsePackages && values.isPackage == true))

        guard descend else {
            let size = isDirectory
                ? FileSize.allocatedSize(of: url)
                : Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            record(size: size, url: url)
            return FileNode(url: url, isDirectory: false, size: size, modificationDate: values.contentModificationDate)
        }

        if Task.isCancelled { throw CancellationError() }

        var fmOptions: FileManager.DirectoryEnumerationOptions = []
        if !options.includeHidden { fmOptions.insert(.skipsHiddenFiles) }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: resourceKeys, options: fmOptions
        )) ?? []

        let keySet = Set(resourceKeys)
        var children: [FileNode] = []
        children.reserveCapacity(contents.count)
        for child in contents {
            if options.excludedPaths.contains(child.path) { continue }
            guard let childValues = try? child.resourceValues(forKeys: keySet) else { continue }
            if options.stayOnVolume, let rootVolume,
               let volume = childValues.volumeIdentifier as? NSObject, !rootVolume.isEqual(volume) {
                continue
            }
            children.append(try makeNode(child, values: childValues))
        }
        return FileNode(url: url, isDirectory: true, size: 0, modificationDate: values.contentModificationDate, children: children)
    }

    private func record(size: Int64, url: URL) {
        filesScanned += 1
        bytesScanned += size
        if filesScanned % progressInterval == 0, let progressHandler {
            progressHandler(ScanProgress(filesScanned: filesScanned, bytesScanned: bytesScanned, currentPath: url.path))
        }
    }
}
