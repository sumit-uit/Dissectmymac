@testable import DissectCore
import XCTest

final class LicenseTests: XCTestCase {
    // Test-only key pair generated with scripts/license_tool.py. The private half was discarded;
    // it is NOT the production key.
    let testPublicKey = "nPilAgtMoVG/0GX4qUvp6pSF6H6OdRYaCVl0veIAMYo="
    let validKey = "DMM1-eyJlbWFpbCI6InRlc3RAZXhhbXBsZS5jb20iLCJpc3N1ZWQiOiIyMDI2LTA5LTI2Iiwib3JkZXIiOiJULTEiLCJwcm9kdWN0IjoiZGlzc2VjdG15bWFjLXBybyJ9.3EmvHgt07LXUTFhxnEo9W_pOjttbcxBsZSClbZ3nMwbQFWy_iCbjh6FSEIGSGc6S_Ngm4b1659oIMtt-YM_PBA"
    let otherProductKey = "DMM1-eyJlbWFpbCI6InhAeS56IiwiaXNzdWVkIjoiMjAyNi0wMS0wMSIsInByb2R1Y3QiOiJvdGhlci1hcHAifQ.dLMvlZr0_YPpoKXG9HlP_CQNJwvcMvhdNwBBpLfbvI9BRya_WRxzKDk_AEdLP8EZx8gyjflZ3jhM22iesDOmBA"

    func testValidKeyVerifies() throws {
        let license = try LicenseVerifier(publicKeyBase64: testPublicKey).verify("  \(validKey)\n")
        XCTAssertEqual(license, License(email: "test@example.com", product: "dissectmymac-pro", issued: "2026-09-26", order: "T-1"))
    }

    func testTamperedPayloadIsRejected() {
        // Swap one character of the payload.
        var chars = Array(validKey)
        let index = LicenseVerifier.prefix.count + 10
        chars[index] = chars[index] == "A" ? "B" : "A"
        XCTAssertThrowsError(try LicenseVerifier(publicKeyBase64: testPublicKey).verify(String(chars)))
    }

    func testWrongPublicKeyIsRejected() {
        let other = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        XCTAssertThrowsError(try LicenseVerifier(publicKeyBase64: other).verify(validKey)) { error in
            XCTAssertEqual(error as? LicenseError, .invalidSignature)
        }
    }

    func testWrongProductIsRejected() {
        XCTAssertThrowsError(try LicenseVerifier(publicKeyBase64: testPublicKey).verify(otherProductKey)) { error in
            XCTAssertEqual(error as? LicenseError, .wrongProduct)
        }
    }

    func testGarbageIsMalformed() {
        for key in ["", "hello", "DMM1-", "DMM1-abc", "DMM1-a.b.c"] {
            XCTAssertThrowsError(try LicenseVerifier(publicKeyBase64: testPublicKey).verify(key), key)
        }
    }
}
