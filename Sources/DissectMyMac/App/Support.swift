import AppKit
import Foundation
import UserNotifications

enum Notifications {
    /// UNUserNotificationCenter crashes in a process without a bundle identifier (e.g. `swift run`).
    private static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static func requestPermission() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Builds a reproducible sample folder for demos and UI-test screenshots (`DMM_AUTOSCAN=demo`).
enum DemoData {
    static func makeSampleFolder() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DissectMyMac Demo")
        try? FileManager.default.removeItem(at: root)
        let files: [(String, Int)] = [
            ("Movies/Vacation 2025.mov", 48_000_000),
            ("Movies/Drone footage.mp4", 31_000_000),
            ("Movies/Screen recording.mov", 12_000_000),
            ("Photos/IMG_0001.heic", 3_200_000),
            ("Photos/IMG_0002.heic", 2_900_000),
            ("Photos/IMG_0002 copy.heic", 2_900_000),
            ("Photos/Raw/DSC_4410.nef", 9_500_000),
            ("Music/Album/01 Intro.m4a", 6_000_000),
            ("Music/Album/02 Theme.m4a", 7_500_000),
            ("Documents/Taxes 2025.pdf", 1_800_000),
            ("Documents/Report.docx", 900_000),
            ("Documents/Old/Report.docx", 900_000),
            ("Downloads/Xcode_16.xip", 22_000_000),
            ("Downloads/Installer.dmg", 14_000_000),
            ("Downloads/archive.zip", 5_000_000),
            ("Projects/webapp/package.json", 2_000),
            ("Projects/webapp/node_modules/react/index.js", 8_000_000),
            ("Projects/webapp/src/App.tsx", 20_000),
            ("Projects/rust-cli/Cargo.toml", 1_000),
            ("Projects/rust-cli/target/debug/app", 11_000_000),
        ]
        for (path, size) in files {
            let url = root.appendingPathComponent(path)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Duplicate files share contents so the duplicate finder has something to show.
            let seed = UInt8(truncatingIfNeeded: url.lastPathComponent.replacingOccurrences(of: " copy", with: "").hashValue & 0xFF)
            try? Data(repeating: seed, count: size).write(to: url)
        }
        return root
    }
}
