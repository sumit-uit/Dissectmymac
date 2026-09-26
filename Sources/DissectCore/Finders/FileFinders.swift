import Foundation

/// Queries over an already-scanned tree: large files, old files, and power search.
public enum FileFinders {
    /// The `limit` largest regular files under `root`, largest first.
    public static func largestFiles(in root: FileNode, limit: Int = 200, minimumSize: Int64 = 0) -> [FileNode] {
        var files: [FileNode] = []
        root.forEach { node in
            if !node.isDirectory, node.size >= minimumSize { files.append(node) }
        }
        files.sort { $0.size > $1.size }
        return Array(files.prefix(limit))
    }

    /// Large files that haven't been modified since `date`, largest first.
    public static func oldFiles(in root: FileNode, notModifiedSince date: Date, minimumSize: Int64 = 10_000_000) -> [FileNode] {
        var files: [FileNode] = []
        root.forEach { node in
            guard !node.isDirectory, node.size >= minimumSize, let modified = node.modificationDate else { return }
            if modified < date { files.append(node) }
        }
        return files.sorted { $0.size > $1.size }
    }

    /// Size breakdown by file category (video, images, archives, ...), largest first.
    public static func categoryBreakdown(of root: FileNode) -> [CategoryTotal] {
        var totals: [FileCategory: Int64] = [:]
        root.forEach { node in
            guard !node.isDirectory else { return }
            totals[FileCategory(extension: node.fileExtension), default: 0] += node.size
        }
        return totals.map { CategoryTotal(category: $0.key, bytes: $0.value) }.sorted { $0.bytes > $1.bytes }
    }

    public static func search(_ query: SearchQuery, in root: FileNode, limit: Int = 1000) -> [FileNode] {
        var results: [FileNode] = []
        var stack: [FileNode] = [root]
        while let node = stack.popLast(), results.count < limit {
            if node !== root, query.matches(node) { results.append(node) }
            stack.append(contentsOf: node.children)
        }
        return results.sorted { $0.size > $1.size }
    }
}

public struct CategoryTotal: Identifiable, Sendable, Hashable {
    public var id: FileCategory { category }
    public let category: FileCategory
    public let bytes: Int64
}

public struct SearchQuery: Sendable, Equatable {
    public enum Kind: String, CaseIterable, Sendable { case any, files, folders }

    public var text: String = ""
    public var kind: Kind = .any
    public var minimumSize: Int64 = 0
    public var category: FileCategory?
    public var modifiedBefore: Date?

    public init(text: String = "", kind: Kind = .any, minimumSize: Int64 = 0,
                category: FileCategory? = nil, modifiedBefore: Date? = nil) {
        self.text = text
        self.kind = kind
        self.minimumSize = minimumSize
        self.category = category
        self.modifiedBefore = modifiedBefore
    }

    /// Supports plain substrings and `*` / `?` wildcards, case-insensitive.
    public func matches(_ node: FileNode) -> Bool {
        switch kind {
        case .files where node.isDirectory: return false
        case .folders where !node.isDirectory: return false
        default: break
        }
        if node.size < minimumSize { return false }
        if let category, node.isDirectory || FileCategory(extension: node.fileExtension) != category { return false }
        if let modifiedBefore, let date = node.modificationDate, date >= modifiedBefore { return false }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        if trimmed.contains("*") || trimmed.contains("?") {
            return Self.wildcard(trimmed.lowercased(), matches: node.name.lowercased())
        }
        return node.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    static func wildcard(_ pattern: String, matches name: String) -> Bool {
        let p = Array(pattern), s = Array(name)
        var pi = 0, si = 0, star = -1, mark = 0
        while si < s.count {
            if pi < p.count, p[pi] == "?" || p[pi] == s[si] {
                pi += 1; si += 1
            } else if pi < p.count, p[pi] == "*" {
                star = pi; mark = si; pi += 1
            } else if star != -1 {
                pi = star + 1; mark += 1; si = mark
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}

public enum FileCategory: String, CaseIterable, Sendable, Hashable {
    case video, audio, images, documents, archives, diskImages, code, apps, other

    public init(extension ext: String) {
        switch ext {
        case "mov", "mp4", "m4v", "mkv", "avi", "wmv", "webm", "mpg", "mpeg", "3gp", "braw", "r3d", "mxf":
            self = .video
        case "mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "caf", "logicx":
            self = .audio
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "raw", "cr2", "cr3", "nef", "arw", "dng",
             "psd", "webp", "bmp", "svg":
            self = .images
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "rtf", "md",
             "csv", "epub":
            self = .documents
        case "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "zst":
            self = .archives
        case "dmg", "iso", "img", "sparseimage", "sparsebundle", "vmdk", "vdi", "qcow2", "ipsw", "pkg":
            self = .diskImages
        case "swift", "m", "h", "c", "cpp", "js", "ts", "py", "rb", "go", "rs", "java", "kt", "json", "yml", "yaml":
            self = .code
        case "app":
            self = .apps
        default:
            self = .other
        }
    }

    public var title: String {
        switch self {
        case .video: return "Video"
        case .audio: return "Audio"
        case .images: return "Images"
        case .documents: return "Documents"
        case .archives: return "Archives"
        case .diskImages: return "Disk Images & Installers"
        case .code: return "Code"
        case .apps: return "Apps"
        case .other: return "Other"
        }
    }
}
