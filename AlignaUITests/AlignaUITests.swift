import XCTest

final class AlignaUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOptionalVoiceSetupIntroductionIsAccessible() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingVoiceSetup"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Help Aligna recognize you"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["Set up my voice"].exists)
        XCTAssertTrue(app.buttons["Skip for now"].exists)
    }

    @MainActor
    func testVoiceSetupLaunchPerformance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingVoiceSetup"]
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }
}
