@testable import DissectCore
import XCTest

final class SystemTests: XCTestCase {
    func testSnapshotParsing() {
        let output = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-09-26-101500.local
        com.apple.os.update-ABCDEF
        garbage line
        """
        let snapshots = HiddenSpace.parseSnapshots(output)
        XCTAssertEqual(snapshots.map(\.name), ["com.apple.TimeMachine.2026-09-26-101500.local", "com.apple.os.update-ABCDEF"])
        XCTAssertEqual(snapshots.first?.dateToken, "2026-09-26-101500")
        XCTAssertNil(snapshots.last?.dateToken)
    }

    func testVolumeUsageMath() {
        let usage = VolumeUsage(total: 1000, availableForImportantUsage: 400, availableNow: 150)
        XCTAssertEqual(usage.purgeable, 250)
        XCTAssertEqual(usage.used, 850)
        XCTAssertNotNil(VolumeUsage.current())
    }

    func testProcessMonitorSeesThisProcess() {
        let monitor = ProcessMonitor()
        _ = monitor.sample()
        let samples = monitor.sample()
        let me = samples.first { $0.pid == ProcessInfo.processInfo.processIdentifier }
        XCTAssertNotNil(me)
        XCTAssertGreaterThan(me?.memory ?? 0, 0)
    }

    func testTrashWatcherReportsNewApps() throws {
        let trash = FileManager.default.temporaryDirectory.appendingPathComponent("dmm-trash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: trash) }
        try FileManager.default.createDirectory(at: trash.appendingPathComponent("Old.app"), withIntermediateDirectories: true)

        let reported = Box()
        let watcher = TrashWatcher(trashURL: trash) { app in reported.append(app.name) }
        XCTAssertTrue(watcher.start())
        defer { watcher.stop() }

        let contents = trash.appendingPathComponent("New.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.example.new", "CFBundleName": "New"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        watcher.checkNow()
        XCTAssertEqual(reported.values, ["New"]) // "Old.app" was there before watching started
    }

    func testHiddenSpaceContributorsOnFakeHome() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("dmm-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let cache = home.appendingPathComponent("Library/Caches/com.example")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 50_000).write(to: cache.appendingPathComponent("blob"))
        let items = HiddenSpace.contributors(home: home)
        XCTAssertTrue(items.contains { $0.title == "App caches" && $0.bytes >= 50_000 })
    }
}

private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func append(_ value: String) { lock.lock(); storage.append(value); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return storage }
}
