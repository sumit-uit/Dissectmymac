import AppKit
import DissectCore
import Foundation

@MainActor
final class LicenseManager: ObservableObject {
    /// Your checkout page (Lemon Squeezy / Paddle / Gumroad). The provider emails the key after purchase.
    static let purchaseURL = URL(string: "https://dissectmymac.app/buy")!
    static let price = "$12.99"

    @Published private(set) var license: License?
    @Published var lastError: String?
    /// Set when a free user tries a Pro action; ContentView shows the upgrade sheet.
    @Published var upgradePrompt: ProFeature?

    private let verifier = LicenseVerifier()
    private let storageKey = "licenseKey"

    init() {
        if let key = UserDefaults.standard.string(forKey: storageKey) {
            license = try? verifier.verify(key)
        }
    }

    var isPro: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["DMM_UNLOCK_PRO"] == "1" { return true }
        #endif
        return license != nil
    }

    @discardableResult
    func activate(_ key: String) -> Bool {
        do {
            license = try verifier.verify(key)
            UserDefaults.standard.set(key.trimmingCharacters(in: .whitespacesAndNewlines), forKey: storageKey)
            lastError = nil
            upgradePrompt = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func deactivate() {
        license = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    /// Returns true if the feature may be used; otherwise shows the upgrade sheet.
    func require(_ feature: ProFeature) -> Bool {
        if isPro { return true }
        upgradePrompt = feature
        return false
    }
}
