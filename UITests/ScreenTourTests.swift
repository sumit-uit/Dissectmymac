import XCTest

/// Drives the app like a person would — clicks through every screen and presses the main buttons —
/// and saves a screenshot of each step. CI exports the screenshots so they can be reviewed.
final class ScreenTourTests: XCTestCase {
    private var app: XCUIApplication!
    private var step = 0

    private let sections = [
        "Storage Map", "Space Overview", "Large & Old Files", "Power Search", "Live Monitor",
        "Junk Cleaner", "App Uninstaller", "Leftover Cleanup", "Duplicate Finder", "Developer Cleanup", "Startup Items",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchEnvironment["DMM_AUTOSCAN"] = "demo"
        app.launchEnvironment["DMM_UI_TEST"] = "1"
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func testTourAsProUser() throws {
        app.launchEnvironment["DMM_UNLOCK_PRO"] = "1"
        app.launchEnvironment["DMM_ONBOARDING"] = "show"
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15), "Main window never appeared")

        // Onboarding: 3 steps.
        snap("onboarding-1-welcome")
        clickButton("Continue")
        snap("onboarding-2-full-disk-access")
        clickButton(["Continue", "Skip for Now"])
        snap("onboarding-3-first-scan")
        clickButton("Done")

        for title in sections {
            let item = sidebarItem(title)
            guard item.waitForExistence(timeout: 5) else {
                XCTFail("Sidebar item '\(title)' not found")
                continue
            }
            item.click()
            sleep(2)
            snap(title)

            switch title {
            case "Storage Map":
                // Drill into the biggest folder in the treemap, then go back up.
                let map = window.otherElements.firstMatch
                if map.exists { window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45)).click() }
                sleep(1)
                snap("Storage Map - drilled in")
            case "Junk Cleaner":
                clickButton("Scan for Junk", wait: 30)
                snap("Junk Cleaner - results")
            case "Leftover Cleanup":
                clickButton("Find Leftovers", wait: 30)
                snap("Leftover Cleanup - results")
            case "Duplicate Finder":
                clickButton("Find Duplicates", wait: 20)
                snap("Duplicate Finder - results")
            case "Power Search":
                let field = window.textFields.firstMatch
                if field.waitForExistence(timeout: 3) {
                    field.click()
                    field.typeText("*.mov")
                    sleep(1)
                    snap("Power Search - results")
                }
            case "App Uninstaller":
                sleep(3)
                let firstApp = window.outlines.element(boundBy: 1).cells.firstMatch
                if firstApp.exists { firstApp.click(); sleep(2); snap("App Uninstaller - app selected") }
            default:
                break
            }
        }

        // Settings window.
        app.typeKey(",", modifierFlags: .command)
        sleep(2)
        snapScreen("Settings")
    }

    func testFreeUserSeesUpgrade() throws {
        app.launchEnvironment["DMM_ONBOARDING"] = "skip"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        sleep(2)
        clickButton(["Upgrade to Pro · $12.99"])
        sleep(1)
        snapScreen("Upgrade sheet")
    }

    // MARK: Helpers

    private func sidebarItem(_ title: String) -> XCUIElement {
        let outlineText = app.outlines.staticTexts[title]
        return outlineText.exists ? outlineText : app.staticTexts[title].firstMatch
    }

    private func clickButton(_ titles: [String], wait: TimeInterval = 3) {
        for title in titles {
            let button = app.buttons[title].firstMatch
            if button.waitForExistence(timeout: 2), button.isEnabled {
                button.click()
                sleep(UInt32(min(wait, 3)))
                // Wait for long-running work (progress indicators) to finish.
                let deadline = Date().addingTimeInterval(wait)
                while app.progressIndicators.firstMatch.exists, Date() < deadline { sleep(1) }
                return
            }
        }
        XCTFail("None of the buttons \(titles) were found")
    }

    private func clickButton(_ title: String, wait: TimeInterval = 3) {
        clickButton([title], wait: wait)
    }

    private func snap(_ name: String) {
        step += 1
        let shot = app.windows.firstMatch.exists ? app.windows.firstMatch.screenshot() : XCUIScreen.main.screenshot()
        attach(shot, name: name)
    }

    private func snapScreen(_ name: String) {
        step += 1
        attach(XCUIScreen.main.screenshot(), name: name)
    }

    private func attach(_ shot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = String(format: "%02d %@", step, name)
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
