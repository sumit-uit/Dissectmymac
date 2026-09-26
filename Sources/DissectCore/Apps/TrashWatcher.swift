import Foundation

/// Watches ~/.Trash and reports apps the user just dragged there, so their leftovers can be cleaned
/// (AppCleaner's "SmartDelete"). Requires Full Disk Access to read the Trash on recent macOS.
public final class TrashWatcher: @unchecked Sendable {
    public let trashURL: URL
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var known: Set<String> = []
    private let queue = DispatchQueue(label: "dissectmymac.trashwatcher")
    private let onAppTrashed: @Sendable (InstalledApp) -> Void

    public init(trashURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"),
                onAppTrashed: @escaping @Sendable (InstalledApp) -> Void) {
        self.trashURL = trashURL
        self.onAppTrashed = onAppTrashed
    }

    deinit { stop() }

    @discardableResult
    public func start() -> Bool {
        guard source == nil else { return true }
        fileDescriptor = open(trashURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return false }
        known = Set(Self.appNames(in: trashURL))
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: [.write, .rename], queue: queue)
        source.setEventHandler { [weak self] in self?.check() }
        let fd = fileDescriptor
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
        return true
    }

    public func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    /// Re-checks the Trash immediately (serialized with file-system events). Used by tests.
    func checkNow() {
        queue.sync { check() }
    }

    /// Diff the Trash against the last listing. Always called on `queue`.
    private func check() {
        let current = Set(Self.appNames(in: trashURL))
        let added = current.subtracting(known)
        known = current
        for name in added.sorted() {
            if let app = AppCatalog.app(at: trashURL.appendingPathComponent(name), computeSize: true) {
                onAppTrashed(app)
            }
        }
    }

    static func appNames(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".app") }
    }
}
