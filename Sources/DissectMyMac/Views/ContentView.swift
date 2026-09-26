import AppKit
import DissectCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var license: LicenseManager
    @State private var hasFullDiskAccess = FinderActions.hasFullDiskAccess
    @State private var showingUpgrade = false

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                Section("Analyze") {
                    ForEach(SidebarSection.analyze) { row($0) }
                }
                Section("Clean Up") {
                    ForEach(SidebarSection.clean) { row($0) }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) { sidebarFooter }
        } detail: {
            VStack(spacing: 0) {
                if !hasFullDiskAccess { fullDiskAccessBanner }
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(item: $license.upgradePrompt) { feature in
            UpgradeView(highlight: feature).environmentObject(license)
        }
        .sheet(isPresented: $showingUpgrade) {
            UpgradeView(highlight: nil).environmentObject(license)
        }
        .alert("Done", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFullDiskAccess = FinderActions.hasFullDiskAccess
        }
    }

    private func row(_ section: SidebarSection) -> some View {
        Label {
            HStack {
                Text(section.title)
                if section.proFeature != nil && !license.isPro {
                    Spacer()
                    Text("PRO").font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(.quaternary))
                }
            }
        } icon: {
            Image(systemName: section.systemImage)
        }
        .tag(section)
    }

    @ViewBuilder
    private var sidebarFooter: some View {
        if license.isPro {
            Label("Pro unlocked", systemImage: "checkmark.seal.fill")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        } else {
            Button {
                showingUpgrade = true
            } label: {
                Label("Upgrade to Pro · \(LicenseManager.price)", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    private var fullDiskAccessBanner: some View {
        HStack {
            Image(systemName: "lock.shield").foregroundStyle(.orange)
            Text("Grant Full Disk Access so DissectMyMac can see Mail, Safari, Messages and other protected folders. Everything stays on your Mac.")
                .font(.callout)
            Spacer()
            Button("Open Settings") { FinderActions.openFullDiskAccessSettings() }
            Button("Dismiss") { hasFullDiskAccess = true }.buttonStyle(.borderless)
        }
        .padding(10)
        .background(.orange.opacity(0.12))
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection ?? .storage {
        case .storage: StorageView()
        case .largeFiles: LargeFilesView()
        case .search: SearchView()
        case .liveStats: LiveStatsView()
        case .junk: JunkCleanerView()
        case .uninstaller: UninstallerView()
        case .leftovers: LeftoversView()
        case .duplicates: DuplicatesView()
        case .devCleaner: DevCleanerView()
        case .startup: StartupItemsView()
        }
    }
}
