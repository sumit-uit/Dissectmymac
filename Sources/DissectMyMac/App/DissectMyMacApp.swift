import AppKit
import DissectCore
import SwiftUI

@main
struct DissectMyMacApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var license = LicenseManager()
    @StateObject private var stats = StatsModel()
    @StateObject private var updater = UpdaterModel()
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage("theme") private var themeID = AppTheme.system.rawValue

    private var theme: AppTheme {
        let theme = AppTheme(rawValue: themeID) ?? .system
        return theme.isPremium && !license.isPro ? .system : theme
    }

    var body: some Scene {
        WindowGroup("DissectMyMac") {
            ContentView()
                .environmentObject(model)
                .environmentObject(license)
                .environmentObject(stats)
                .environment(\.appTheme, theme)
                .tint(theme.accent)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            CommandGroup(after: .newItem) {
                Button("Scan Home Folder") { model.scan(FileManager.default.homeDirectoryForCurrentUser) }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("Scan Folder…") {
                    if let url = FinderActions.chooseFolder() { model.scan(url) }
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }

        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarStatsView()
                .environmentObject(stats)
                .environment(\.appTheme, theme)
        } label: {
            MenuBarLabel(stats: stats)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(license)
                .environmentObject(model)
                .environmentObject(updater)
                .environment(\.appTheme, theme)
        }
    }
}
