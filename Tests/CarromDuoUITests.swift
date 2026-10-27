import XCTest

final class CarromDuoUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(result: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CARROM_UI_TEST"] = "1"
        app.launchEnvironment["CARROM_UI_RESULT"] = result
        app.launch()
        return app
    }

    func testVictoryReplayThenHomeAndNewMatch() {
        let app = launch(result: "win")
        XCTAssertTrue(app.staticTexts["YOU WON!"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["new-game"].firstMatch.isHittable)
        attachScreenshot("Victory portrait")
        app.buttons["play-again"].tap()
        XCTAssertTrue(app.buttons["new-game"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["play-again"].exists)
        XCTAssertEqual(app.staticTexts["score-1"].firstMatch.label, "0")
        XCTAssertEqual(app.staticTexts["score-2"].firstMatch.label, "0")
        app.buttons["home-button"].firstMatch.tap()
        XCTAssertTrue(app.buttons["demo-play"].waitForExistence(timeout: 5))
        app.buttons["demo-play"].tap()
        XCTAssertTrue(app.buttons["new-game"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["score-1"].firstMatch.label, "0")
    }

    func testDefeatAndReturnHome() {
        let app = launch(result: "loss")
        XCTAssertTrue(app.staticTexts["YOU LOST!"].waitForExistence(timeout: 10))
        attachScreenshot("Defeat portrait")
        app.buttons["back-to-home"].tap()
        let reachedHome = app.buttons["demo-play"].waitForExistence(timeout: 5)
        if !reachedHome {
            attachScreenshot("Home navigation failure")
            print(app.debugDescription)
        }
        XCTAssertTrue(reachedHome)
        XCTAssertFalse(app.staticTexts["YOU LOST!"].exists)
    }

    func testLandscapeResultButtonsRemainAccessible() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch(result: "win")
        XCTAssertTrue(app.staticTexts["YOU WON!"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["play-again"].isHittable)
        XCTAssertTrue(app.buttons["back-to-home"].isHittable)
        attachScreenshot("Victory landscape")
        app.buttons["back-to-home"].tap()
        XCUIDevice.shared.orientation = .portrait
    }

    func testMusicAndEffectsControlsAreIndependent() {
        let app = launch()
        XCTAssertTrue(app.buttons["audio-settings"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["audio-settings"].firstMatch.tap()
        let music = app.switches["music-toggle"]
        let effects = app.switches["effects-toggle"]
        XCTAssertTrue(music.waitForExistence(timeout: 5))
        XCTAssertEqual(music.value as? String, "1")
        XCTAssertEqual(effects.value as? String, "1")
        music.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(music.value as? String, "0")
        XCTAssertEqual(effects.value as? String, "1")
        effects.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(effects.value as? String, "0")
        music.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(music.value as? String, "1")
        XCTAssertEqual(effects.value as? String, "0")
        app.buttons["Done"].tap()
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
