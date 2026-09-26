import AppKit
import DissectCore
import SwiftUI

struct UpgradeView: View {
    let highlight: ProFeature?
    @EnvironmentObject private var license: LicenseManager
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""

    private let freeFeatures = ["Storage map (treemap)", "Large & old files", "Power search", "Live monitor + menu bar",
                                "Scan for junk, duplicates & leftovers"]

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(.tint)
            Text("DissectMyMac Pro").font(.largeTitle.bold())
            if let highlight {
                Text("\(highlight.title) is part of Pro.").foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 24) {
                featureColumn("Free", features: freeFeatures, symbol: "checkmark")
                featureColumn("Pro · \(LicenseManager.price) once",
                              features: ["Everything in Free"] + ProFeature.allCases.map(\.title),
                              symbol: "checkmark.seal.fill")
            }
            Text("One-time purchase. No subscription, no account, works offline. 15-day money-back guarantee.")
                .font(.callout).foregroundStyle(.secondary)
            Link(destination: LicenseManager.purchaseURL) {
                Text("Buy Pro for \(LicenseManager.price)").frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Divider()
            LicenseEntry(key: $key)
            Button("Not Now") { dismiss() }.buttonStyle(.borderless)
        }
        .padding(28)
        .frame(width: 560)
        .onChange(of: license.isPro) { _, isPro in if isPro { dismiss() } }
    }

    private func featureColumn(_ title: String, features: [String], symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            ForEach(features, id: \.self) { feature in
                Label(feature, systemImage: symbol)
                    .fontWeight(ProFeature.allCases.first { $0.title == feature } == highlight && highlight != nil ? .bold : .regular)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LicenseEntry: View {
    @Binding var key: String
    @EnvironmentObject private var license: LicenseManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Already purchased? Paste your license key:").font(.callout)
            HStack {
                TextField("DMM1-…", text: $key).textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                Button("Activate") { license.activate(key) }.disabled(key.isEmpty)
            }
            if let error = license.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var license: LicenseManager
    @AppStorage("theme") private var themeID = AppTheme.system.rawValue
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @State private var key = ""

    var body: some View {
        TabView {
            Form {
                Toggle("Show live monitor in the menu bar", isOn: $showMenuBarExtra)
                Picker("Theme", selection: $themeID) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.isPremium && !license.isPro ? "\(theme.title) (Pro)" : theme.title).tag(theme.rawValue)
                    }
                }
                .onChange(of: themeID) { _, newValue in
                    if AppTheme(rawValue: newValue)?.isPremium == true, !license.require(.themes) {
                        themeID = AppTheme.system.rawValue
                    }
                }
                LabeledContent("Full Disk Access") {
                    HStack {
                        Text(FinderActions.hasFullDiskAccess ? "Granted" : "Not granted")
                        Button("Open Settings") { FinderActions.openFullDiskAccessSettings() }
                    }
                }
            }
            .padding()
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                if let current = license.license {
                    LabeledContent("Status", value: "Pro")
                    LabeledContent("Licensed to", value: current.email)
                    LabeledContent("Issued", value: current.issued)
                    Button("Deactivate on This Mac") { license.deactivate() }
                } else {
                    LabeledContent("Status", value: "Free")
                    LicenseEntry(key: $key)
                    Link("Buy Pro (\(LicenseManager.price))", destination: LicenseManager.purchaseURL)
                }
            }
            .padding()
            .tabItem { Label("License", systemImage: "key") }

            Form {
                Text("DissectMyMac analyzes everything on your Mac. No files, file names or usage data are ever uploaded. There is no account and no analytics.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 520, height: 300)
        .sheet(item: $license.upgradePrompt) { feature in
            UpgradeView(highlight: feature).environmentObject(license)
        }
    }
}
