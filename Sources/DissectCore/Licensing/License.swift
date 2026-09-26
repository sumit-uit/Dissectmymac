import CryptoKit
import Foundation

/// An offline-verifiable Pro license. No server, no account, no activation call.
///
/// Key format: `DMM1-<base64url(JSON payload)>.<base64url(Ed25519 signature of the payload bytes)>`
///
/// Keys are issued by `scripts/license_tool.py` (or a webhook on your payment provider running the
/// same logic) with the private key. The app only ships the public key, so it can check a key's
/// authenticity but can never mint one.
public struct License: Codable, Equatable, Sendable {
    public let email: String
    public let product: String
    /// ISO-8601 date the license was issued.
    public let issued: String
    /// Optional order reference from the payment provider.
    public let order: String?

    public init(email: String, product: String, issued: String, order: String? = nil) {
        self.email = email
        self.product = product
        self.issued = issued
        self.order = order
    }
}

public enum LicenseError: Error, Equatable, LocalizedError {
    case malformed
    case invalidSignature
    case wrongProduct

    public var errorDescription: String? {
        switch self {
        case .malformed: return "That doesn't look like a DissectMyMac license key."
        case .invalidSignature: return "This license key is not valid."
        case .wrongProduct: return "This license key is for a different product."
        }
    }
}

public struct LicenseVerifier: Sendable {
    public static let prefix = "DMM1-"
    public static let productID = "dissectmymac-pro"

    /// Replace with the public key printed by `python3 scripts/license_tool.py keygen`.
    public static let productionPublicKey = "REPLACE_WITH_YOUR_PUBLIC_KEY_BASE64"

    private let publicKey: Curve25519.Signing.PublicKey?

    public init(publicKeyBase64: String = LicenseVerifier.productionPublicKey) {
        if let raw = Data(base64Encoded: publicKeyBase64) {
            publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
        } else {
            publicKey = nil
        }
    }

    public func verify(_ key: String) throws -> License {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(Self.prefix) else { throw LicenseError.malformed }
        let body = trimmed.dropFirst(Self.prefix.count)
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let payload = Self.base64URLDecode(String(parts[0])),
              let signature = Self.base64URLDecode(String(parts[1])) else {
            throw LicenseError.malformed
        }
        guard let publicKey, publicKey.isValidSignature(signature, for: payload) else {
            throw LicenseError.invalidSignature
        }
        guard let license = try? JSONDecoder().decode(License.self, from: payload) else {
            throw LicenseError.malformed
        }
        guard license.product == Self.productID else { throw LicenseError.wrongProduct }
        return license
    }

    static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder == 1 { return nil }
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: base64)
    }
}

/// Features that require Pro. Everything else is free.
public enum ProFeature: String, CaseIterable, Identifiable, Sendable {
    public var id: String { rawValue }

    case uninstaller, leftovers, junkCleaner, duplicates, devCleaner, startupItems, themes

    public var title: String {
        switch self {
        case .uninstaller: return "App Uninstaller"
        case .leftovers: return "Leftover Cleanup"
        case .junkCleaner: return "Junk Cleaner"
        case .duplicates: return "Duplicate Finder"
        case .devCleaner: return "Developer Cleanup"
        case .startupItems: return "Startup Items"
        case .themes: return "Premium Themes"
        }
    }
}
