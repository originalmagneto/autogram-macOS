import XCTest
import Chevron7Identity
@testable import Chevron7WebBridge

/// Every name macOS knows the product by. The literals are repeated on purpose:
/// build_app.sh and the scripts carry the same strings, and a changed value here
/// must be changed there too.
final class ProductIdentityTests: XCTestCase {
    func testBundleNamesShareOnePrefix() {
        XCTAssertEqual(ProductIdentity.name, "Chevron7")
        XCTAssertEqual(ProductIdentity.bundleIdentifier, "app.slovensko.chevron7")
        XCTAssertEqual(ProductIdentity.webExtensionBundleIdentifier, "app.slovensko.chevron7.WebExtension")
        XCTAssertEqual(ProductIdentity.webBridgeServiceName, "app.slovensko.chevron7.webbridge")
        XCTAssertEqual(ProductIdentity.urlScheme, "chevron7")
        XCTAssertEqual(ProductIdentity.installedAppURL.path, "/Applications/Chevron7.app")
    }

    func testWebBridgeUsesTheIdentity() {
        XCTAssertEqual(WebSigningBridge.machServiceName, "app.slovensko.chevron7.webbridge")
        XCTAssertEqual(WebSigningBridge.agentLabel, "app.slovensko.chevron7.webbridge")
    }

    func testDataRootsAreNamedAfterTheProduct() {
        XCTAssertEqual(ProductIdentity.applicationSupportDirectory().lastPathComponent, "Chevron7")
        XCTAssertEqual(ProductIdentity.applicationSupportDirectory().deletingLastPathComponent().lastPathComponent, "Application Support")
        XCTAssertEqual(ProductIdentity.cachesDirectory().lastPathComponent, "Chevron7")
        XCTAssertEqual(ProductIdentity.cachesDirectory().deletingLastPathComponent().lastPathComponent, "Caches")
    }
}
