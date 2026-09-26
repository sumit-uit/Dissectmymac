import AppKit
import DissectCore
import SwiftUI

/// Lists launchd agents and daemons — the background items that start with your Mac.
struct StartupItemsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var license: LicenseManager
    @State private var items: [StartupItem] = []
    @State private var pendingRemoval: StartupItem?

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Startup Items",
                          subtitle: "Background agents and daemons that launch at login or boot.") {
                HStack {
                    Button("Login Items Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            Table(items) {
                TableColumn("Label") { item in
                    HStack {
                        if item.isBroken {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                .help("The program this item launches no longer exists — likely left behind by a deleted app.")
                        }
                        Text(item.label)
                    }
                }
                TableColumn("Type") { Text($0.scope.rawValue) }.width(110)
                TableColumn("At Load") { Text($0.runAtLoad ? "Yes" : "No") }.width(60)
                TableColumn("Keep Alive") { Text($0.keepAlive ? "Yes" : "No") }.width(70)
                TableColumn("Program") { Text($0.program ?? "—").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                TableColumn("") { item in
                    HStack {
                        Button { FinderActions.reveal([item.plistURL]) } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.borderless)
                            .help("Reveal in Finder")
                        if item.isUserRemovable {
                            Button {
                                if license.require(.startupItems) { pendingRemoval = item }
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help("Move to Trash")
                        }
                    }
                }
                .width(60)
            }
            Text("System-wide items in /Library need an administrator to remove; use Reveal in Finder. Changes take effect after you log out.")
                .font(.caption).foregroundStyle(.secondary).padding(8)
        }
        .task { reload() }
        .confirmationDialog("Remove “\(pendingRemoval?.label ?? "")”?",
                            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let item = pendingRemoval {
                    model.report(Trash.moveToTrash([item.plistURL]))
                    reload()
                }
                pendingRemoval = nil
            }
        } message: {
            Text("The agent will no longer start at login. It keeps running until you log out or restart.")
        }
    }

    private func reload() {
        items = StartupItems.all()
    }
}
