import Foundation

/// A regenerable build/dependency folder inside a code project (npkill / DevCleaner style).
public struct ProjectArtifact: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let kind: String
    public let projectURL: URL
    public let size: Int64
    public let lastModified: Date?
}

public enum DevProjectScanner {
    /// Folder name → (kind, marker file that must exist in the parent to confirm it's really a project).
    static let rules: [String: (kind: String, markers: [String])] = [
        "node_modules": ("Node.js dependencies", ["package.json"]),
        "Pods": ("CocoaPods", ["Podfile"]),
        ".build": ("Swift Package build", ["Package.swift"]),
        "DerivedData": ("Xcode DerivedData", []),
        "target": ("Rust / Maven build", ["Cargo.toml", "pom.xml"]),
        "build": ("Gradle / generic build", ["build.gradle", "build.gradle.kts", "CMakeLists.txt", "package.json"]),
        ".gradle": ("Gradle cache", ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]),
        "venv": ("Python virtualenv", ["requirements.txt", "pyproject.toml", "setup.py"]),
        ".venv": ("Python virtualenv", ["requirements.txt", "pyproject.toml", "setup.py"]),
        "__pycache__": ("Python bytecode", []),
        ".next": ("Next.js build", ["package.json"]),
        ".nuxt": ("Nuxt build", ["package.json"]),
        "dist": ("JS build output", ["package.json"]),
        ".parcel-cache": ("Parcel cache", ["package.json"]),
        ".turbo": ("Turborepo cache", ["package.json"]),
        "vendor": ("Composer / Go vendor", ["composer.json", "go.mod"]),
    ]

    static let skippedFolders: Set<String> = [".git", "Library", ".Trash", "Applications", "System"]

    public static func scan(roots: [URL], maxDepth: Int = 8) throws -> [ProjectArtifact] {
        var results: [ProjectArtifact] = []
        let fm = FileManager.default

        func visit(_ folder: URL, depth: Int) throws {
            if Task.isCancelled { throw CancellationError() }
            guard depth <= maxDepth else { return }
            let entries = (try? fm.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []
            )) ?? []
            let names = Set(entries.map(\.lastPathComponent))
            for entry in entries {
                guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true, values.isSymbolicLink != true else { continue }
                let name = entry.lastPathComponent
                if let rule = rules[name], rule.markers.isEmpty || rule.markers.contains(where: { names.contains($0) }) {
                    let modified = try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                    results.append(ProjectArtifact(url: entry, kind: rule.kind, projectURL: folder,
                                                   size: FileSize.allocatedSize(of: entry), lastModified: modified))
                    continue // never descend into an artifact folder
                }
                if skippedFolders.contains(name) || entry.pathExtension == "app" { continue }
                try visit(entry, depth: depth + 1)
            }
        }

        for root in roots { try visit(root, depth: 0) }
        return results.sorted { $0.size > $1.size }
    }
}
