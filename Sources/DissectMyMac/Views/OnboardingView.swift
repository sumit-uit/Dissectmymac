import AppKit
import DissectCore
import SwiftUI

/// First-launch walkthrough: privacy promise → Full Disk Access → first scan.
struct OnboardingView: View {
    var onFinish: () -> Void
    @EnvironmentObject private var model: AppModel
    @State private var step = 0
    @State private var hasAccess = FinderActions.hasFullDiskAccess
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            Group {
                switch step {
                case 0: welcome
                case 1: fullDiskAccess
                default: firstScan
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                ForEach(0..<3) { index in
                    Circle().fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
                }
                Spacer()
                if step > 0 { Button("Back") { step -= 1 } }
                if step < 2 {
                    Button(step == 1 && !hasAccess ? "Skip for Now" : "Continue") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done", action: onFinish).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 560, height: 420)
        .onReceive(timer) { _ in hasAccess = FinderActions.hasFullDiskAccess }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.3x3.square").font(.system(size: 60)).foregroundStyle(.tint)
            Text("Welcome to DissectMyMac").font(.largeTitle.bold())
            Text("See what's taking up space, clean junk, uninstall apps completely, and watch your Mac's vitals.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Label("Everything runs on your Mac. No account, no uploads, no tracking.", systemImage: "lock.shield")
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
        }
    }

    private var fullDiskAccess: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(hasAccess ? "Full Disk Access granted" : "Grant Full Disk Access",
                  systemImage: hasAccess ? "checkmark.seal.fill" : "lock.open")
                .font(.title.bold())
                .foregroundStyle(hasAccess ? .green : .primary)
            Text("macOS hides Mail, Messages, Safari and other folders from every app until you allow it. Without access, scans miss space and cleanup is limited.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Click **Open System Settings** below.")
                Text("2. Turn on **DissectMyMac** in the list (or click + and choose it from Applications).")
                Text("3. Come back here. This page updates automatically.")
            }
            Button("Open System Settings") { FinderActions.openFullDiskAccessSettings() }
                .buttonStyle(.borderedProminent)
                .disabled(hasAccess)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var firstScan: some View {
        VStack(spacing: 14) {
            Image(systemName: "internaldrive").font(.system(size: 50)).foregroundStyle(.tint)
            Text("Start your first scan").font(.title.bold())
            Text("Scanning your home folder takes under a minute on most Macs.").foregroundStyle(.secondary)
            HStack {
                Button("Scan Home Folder") {
                    model.scan(FileManager.default.homeDirectoryForCurrentUser)
                    onFinish()
                }
                .buttonStyle(.borderedProminent)
                Button("Scan Entire Disk") {
                    model.scan(URL(fileURLWithPath: "/"))
                    onFinish()
                }
            }
        }
    }
}

/// Shown when the user drags an app to the Trash: offers to remove the files it left behind.
struct TrashedAppView: View {
    let app: InstalledApp
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var leftovers: [LeftoverItem] = []
    @State private var selected = Set<String>()
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading) {
                    Text("\(app.name) was moved to the Trash").font(.title3.bold())
                    Text("Apps leave settings, caches and support files behind. Remove them too?")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            } else if leftovers.isEmpty {
                Text("No leftover files found. Nothing else to do.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List(leftovers) { item in
                    Toggle(isOn: Binding(get: { selected.contains(item.id) },
                                         set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } })) {
                        FileRow(url: item.url, size: item.size, detail: item.location.title)
                    }
                }
                .frame(minHeight: 200)
            }
            HStack {
                Button("Not Now") { dismiss() }
                Spacer()
            }
            .padding(.horizontal)
            if !leftovers.isEmpty {
                let chosen = leftovers.filter { selected.contains($0.id) }
                CleanBar(selectedCount: chosen.count, selectedBytes: chosen.reduce(0) { $0 + $1.size },
                         actionTitle: "Remove Leftovers", feature: .uninstaller) {
                    model.report(Trash.moveToTrash(chosen.map(\.url)))
                    dismiss()
                }
            }
        }
        .frame(width: 560)
        .task {
            let app = self.app
            let found = await Task.detached {
                LeftoverScanner.leftovers(for: app).filter { !$0.url.path.contains("/.Trash/") }
            }.value
            leftovers = found
            selected = Set(found.map(\.id))
            isLoading = false
        }
    }
}
