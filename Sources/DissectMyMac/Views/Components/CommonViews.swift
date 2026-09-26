import AppKit
import DissectCore
import SwiftUI

/// Title + subtitle header used at the top of every section.
struct SectionHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.bold())
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
        .padding([.horizontal, .top])
        .padding(.bottom, 8)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Shown when a section needs a disk scan first.
struct NeedsScanView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ContentUnavailableView {
            Label("Nothing scanned yet", systemImage: "internaldrive")
        } description: {
            Text("Scan a folder or your whole disk to use this view.")
        } actions: {
            ScanButtons()
        }
    }
}

struct ScanButtons: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack {
            Button("Scan Home Folder") { model.scan(FileManager.default.homeDirectoryForCurrentUser) }
                .buttonStyle(.borderedProminent)
            Button("Scan Macintosh HD") { model.scan(URL(fileURLWithPath: "/")) }
            Button("Choose Folder…") {
                if let url = FinderActions.chooseFolder() { model.scan(url) }
            }
        }
    }
}

struct ScanProgressView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Scanning \(model.scannedURL?.path ?? "")…").font(.headline)
            if let progress = model.progress {
                Text("\(progress.filesScanned.formatted()) files · \(ByteFormat.string(progress.bytesScanned))")
                    .monospacedDigit()
                Text(progress.currentPath)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: 500)
            }
            Button("Cancel") { model.cancelScan() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A row with an icon, a name, a path, and a size.
struct FileRow: View {
    let url: URL
    let size: Int64
    var detail: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).lineLimit(1)
                Text(detail ?? url.deletingLastPathComponent().path)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(ByteFormat.string(size)).monospacedDigit().foregroundStyle(.secondary)
        }
        .contextMenu {
            Button("Reveal in Finder") { FinderActions.reveal([url]) }
            Button("Open") { FinderActions.open(url) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }
        }
    }
}

/// Bottom bar with a total and a destructive action, used by every cleaner.
struct CleanBar: View {
    let selectedCount: Int
    let selectedBytes: Int64
    let actionTitle: String
    var feature: ProFeature?
    let action: () -> Void

    @EnvironmentObject private var license: LicenseManager
    @State private var confirming = false

    var body: some View {
        HStack {
            Text("\(selectedCount) selected · \(ByteFormat.string(selectedBytes))")
                .monospacedDigit().foregroundStyle(.secondary)
            Spacer()
            if let feature, !license.isPro {
                Label("Pro", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
                    .help("\(feature.title) is part of DissectMyMac Pro")
            }
            Button(actionTitle, role: .destructive) {
                if let feature, !license.require(feature) { return }
                confirming = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedCount == 0)
        }
        .padding()
        .background(.bar)
        .confirmationDialog("\(actionTitle)?", isPresented: $confirming) {
            Button("Move \(selectedCount) item(s) to Trash", role: .destructive, action: action)
        } message: {
            Text("\(ByteFormat.string(selectedBytes)) will be moved to the Trash. You can restore items from the Trash until you empty it.")
        }
    }
}

/// Horizontal size bar.
struct SizeBar: View {
    let fraction: Double
    var color: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color).frame(width: max(2, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 6)
    }
}
