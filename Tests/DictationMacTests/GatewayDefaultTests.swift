import DictationCore
import DictationMac
import Foundation
import XCTest

/// G1: select a default using explicit config, without probing this machine's CLIs.
final class GatewayDefaultTests: XCTestCase {
    func test_G1_gatewayFactoryUsesModelInMenuAndHasNoExecutable() {
        let selection = CleanupSelection.gateway(model: "custom/model")

        XCTAssertEqual(selection.backend, .gateway)
        XCTAssertNil(selection.executablePath)
        XCTAssertEqual(selection.menuLabel, "Cleanup: gateway (custom/model)")
    }

    func test_G1_configPresentDefaultsToGatewayWithConfiguredModel() {
        let config = GatewayConfig(
            url: URL(string: "https://gateway.invalid")!,
            model: "custom/model",
            key: "test-only-key"
        )

        let selection = CleanupSelection.defaultSelection(gatewayConfig: config)

        XCTAssertEqual(selection, .gateway(model: config.model))
        XCTAssertEqual(selection.backend, .gateway)
        XCTAssertNil(selection.executablePath)
        XCTAssertEqual(selection.menuLabel, "Cleanup: gateway (custom/model)")
    }

    func test_G1_minimalConfigDefaultsToGatewayWithDefaultModel() {
        let config = GatewayConfig(url: URL(string: "https://gateway.invalid")!, key: "test-only-key")
        let selection = CleanupSelection.defaultSelection(gatewayConfig: config)

        XCTAssertEqual(selection.backend, .gateway)
        XCTAssertEqual(selection.menuLabel, "Cleanup: gateway (deepseek/deepseek-flash)")
        XCTAssertNil(selection.executablePath)
    }

    func test_G1_noConfigDefaultsToLocalRules() {
        let selection = CleanupSelection.defaultSelection(gatewayConfig: nil)

        XCTAssertEqual(selection, .local)
        XCTAssertEqual(selection.backend, .localModel)
        XCTAssertNil(selection.executablePath)
        XCTAssertEqual(selection.menuLabel, CleanupSelection.local.menuLabel)
    }
}
