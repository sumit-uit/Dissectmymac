@testable import DissectCore
import XCTest

final class ScannerTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("dmm-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func write(_ path: String, bytes: Int, fill: UInt8 = 1) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: fill, count: bytes).write(to: url)
        return url
    }

    func testScanBuildsSortedTreeWithTotals() throws {
        try write("big/movie.mov", bytes: 300_000)
        try write("big/clip.mp4", bytes: 100_000)
        try write("small/note.txt", bytes: 10)
        try write("top.zip", bytes: 50_000)

        let tree = try DiskScanner().scan(root)
        XCTAssertEqual(tree.fileCount, 4)
        XCTAssertEqual(tree.children.first?.name, "big")
        XCTAssertEqual(tree.size, tree.children.reduce(0) { $0 + $1.size })
        XCTAssertGreaterThanOrEqual(tree.size, 450_010)

        let largest = FileFinders.largestFiles(in: tree, limit: 2)
        XCTAssertEqual(largest.map(\.name), ["movie.mov", "clip.mp4"])
        XCTAssertEqual(largest.first?.ancestry.first, tree)

        let breakdown = FileFinders.categoryBreakdown(of: tree)
        XCTAssertEqual(breakdown.first?.category, .video)
    }

    func testSearch() throws {
        try write("a/Report-2024.pdf", bytes: 2000)
        try write("a/report-draft.docx", bytes: 1000)
        try write("b/photo.jpg", bytes: 5000)
        let tree = try DiskScanner().scan(root)

        XCTAssertEqual(Set(FileFinders.search(SearchQuery(text: "report"), in: tree).map(\.name)),
                       ["Report-2024.pdf", "report-draft.docx"])
        XCTAssertEqual(FileFinders.search(SearchQuery(text: "*.jpg"), in: tree).map(\.name), ["photo.jpg"])
        XCTAssertEqual(FileFinders.search(SearchQuery(kind: .folders), in: tree).count, 2)
        XCTAssertEqual(FileFinders.search(SearchQuery(category: .documents), in: tree).count, 2)
    }

    func testWildcard() {
        XCTAssertTrue(SearchQuery.wildcard("*.mov", matches: "clip.mov"))
        XCTAssertTrue(SearchQuery.wildcard("img_????.heic", matches: "img_1234.heic"))
        XCTAssertFalse(SearchQuery.wildcard("*.mov", matches: "clip.mp4"))
        XCTAssertTrue(SearchQuery.wildcard("*", matches: ""))
    }

    func testDuplicates() throws {
        try write("one/a.bin", bytes: 200_000, fill: 7)
        try write("two/b.bin", bytes: 200_000, fill: 7)
        try write("three/c.bin", bytes: 200_000, fill: 8) // same size, different content
        try write("d.bin", bytes: 10, fill: 7)
        let tree = try DiskScanner().scan(root)

        let groups = try DuplicateFinder.findDuplicates(in: tree)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].urls.map(\.lastPathComponent)), ["a.bin", "b.bin"])
        XCTAssertEqual(groups[0].wastedBytes, groups[0].fileSize)
    }

    func testDevProjectScanner() throws {
        try write("web/package.json", bytes: 10)
        try write("web/node_modules/left-pad/index.js", bytes: 5000)
        try write("rust/Cargo.toml", bytes: 10)
        try write("rust/target/debug/app", bytes: 8000)
        try write("notes/build/readme.txt", bytes: 100) // no marker → not a project artifact

        let artifacts = try DevProjectScanner.scan(roots: [root])
        XCTAssertEqual(Set(artifacts.map(\.url.lastPathComponent)), ["node_modules", "target"])
    }

    func testJunkScanAndTrashSafety() throws {
        let cache = try write("Library/Caches/com.example/cache.db", bytes: 4096)
        let results = JunkCleaner.scan(JunkCleaner.catalog(home: root).filter { $0.id == "user-caches" })
        XCTAssertEqual(results.first?.items.map(\.lastPathComponent), ["com.example"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
    }
}
