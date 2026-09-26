@testable import DissectCore
import XCTest

final class LeftoverMatcherTests: XCTestCase {
    func testNormalization() {
        XCTAssertEqual(LeftoverMatcher.normalizedIdentifier("com.foo.Bar.plist"), "com.foo.Bar")
        XCTAssertEqual(LeftoverMatcher.normalizedIdentifier("com.foo.Bar.savedState"), "com.foo.Bar")
        XCTAssertEqual(LeftoverMatcher.normalizedIdentifier("ABCDE12345.com.foo.Bar"), "com.foo.Bar")
        XCTAssertEqual(LeftoverMatcher.normalizedIdentifier("Slack"), "Slack")
    }

    func testMatchesByBundleIdentifier() {
        let id = "com.tinyspeck.slackmacgap"
        XCTAssertTrue(LeftoverMatcher.matches(entryName: "com.tinyspeck.slackmacgap.plist", bundleID: id, appName: "Slack", allowNameMatch: false))
        XCTAssertTrue(LeftoverMatcher.matches(entryName: "com.tinyspeck.slackmacgap.ShipIt", bundleID: id, appName: "Slack", allowNameMatch: false))
        XCTAssertTrue(LeftoverMatcher.matches(entryName: "BQR82RBBHL.com.tinyspeck.slackmacgap", bundleID: id, appName: "Slack", allowNameMatch: false))
        XCTAssertFalse(LeftoverMatcher.matches(entryName: "com.tinyspeck.slackmacgapX", bundleID: id, appName: "Slack", allowNameMatch: false))
    }

    func testNameMatchOnlyWhereAllowed() {
        XCTAssertTrue(LeftoverMatcher.matches(entryName: "Slack", bundleID: "com.x", appName: "Slack", allowNameMatch: true))
        XCTAssertFalse(LeftoverMatcher.matches(entryName: "Slack", bundleID: "com.x", appName: "Slack", allowNameMatch: false))
        XCTAssertTrue(LeftoverMatcher.matches(entryName: "VisualStudioCode", bundleID: nil, appName: "Visual Studio Code", allowNameMatch: true))
        // Short names are too ambiguous to match on.
        XCTAssertFalse(LeftoverMatcher.matches(entryName: "Go", bundleID: nil, appName: "Go", allowNameMatch: true))
    }

    func testOrphanDetection() {
        let installed: Set<String> = ["com.google.chrome", "com.microsoft.vscode"]
        XCTAssertTrue(LeftoverMatcher.isOwned("com.google.Chrome", byAnyOf: installed))
        XCTAssertTrue(LeftoverMatcher.isOwned("com.google.chrome.helper", byAnyOf: installed))
        XCTAssertFalse(LeftoverMatcher.isOwned("com.spotify.client", byAnyOf: installed))
        XCTAssertTrue(LeftoverMatcher.looksLikeBundleIdentifier("com.spotify.client.plist"))
        XCTAssertFalse(LeftoverMatcher.looksLikeBundleIdentifier("Spotify"))
        XCTAssertTrue(LeftoverMatcher.isProtected("com.apple.Safari"))
        XCTAssertFalse(LeftoverMatcher.isProtected("com.spotify.client"))
        XCTAssertTrue(LeftoverMatcher.isProtected("group.is.workflow.my.app"))
        XCTAssertTrue(LeftoverMatcher.isProtected("com.dissectmymac.app"))
        XCTAssertTrue(LeftoverMatcher.isProtected("com.example.uitests.xctrunner"))
    }

    func testSafetyPolicy() {
        let home = URL(fileURLWithPath: "/Users/test")
        XCTAssertFalse(SafetyPolicy.isRemovable(URL(fileURLWithPath: "/"), home: home))
        XCTAssertFalse(SafetyPolicy.isRemovable(URL(fileURLWithPath: "/System/Library"), home: home))
        XCTAssertFalse(SafetyPolicy.isRemovable(home, home: home))
        XCTAssertFalse(SafetyPolicy.isRemovable(home.appendingPathComponent("Library/Caches"), home: home))
        XCTAssertTrue(SafetyPolicy.isRemovable(home.appendingPathComponent("Library/Caches/com.foo"), home: home))
        XCTAssertTrue(SafetyPolicy.isRemovable(home.appendingPathComponent("Downloads/big.dmg"), home: home))
    }
}
