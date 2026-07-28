import XCTest

/// The journey the app exists for, driven through the real interface:
/// scan → answer a question → see the note → log it → check in → see it in history.
///
/// `@MainActor` because every XCUITest API is main-actor isolated; without it
/// Swift 6 warns on each `app.…` call.
@MainActor
final class ScanToCheckInUITests: XCTestCase {
    private var app: XCUIApplication!

    // The `async` overrides rather than the `WithError` ones: those are
    // nonisolated on `XCTestCase`, so they would not pick up `@MainActor`.
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // A fresh, session-only store so the test never sees real entries.
        app.launchArguments = ["--uitest"]
        app.launch()
    }

    override func tearDown() async throws {
        app = nil
    }

    func testScanClarifyWarnLogCheckInAndSeeHistory() throws {
        // 1. Scan.
        tap(element("home.scanButton"))
        tap(element("capture.fixture.caffeinatedTea"))

        // 2. Answer the one clarification question.
        let yes = element("clarify.yes")
        XCTAssertTrue(yes.waitForExistence(timeout: 15), "The clarification question should appear")
        XCTAssertTrue(app.staticTexts["Was the tea caffeinated?"].exists)
        tap(yes)

        // 3. See the note, with its heading, reason and suggestion.
        let name = element("result.itemName")
        XCTAssertTrue(name.waitForExistence(timeout: 10), "The result should appear")
        XCTAssertTrue(app.staticTexts["Looks like"].exists)
        XCTAssertTrue(app.staticTexts["Heads up"].exists)
        XCTAssertTrue(
            app.staticTexts["Caffeine can make reflux symptoms worse for some people."].exists,
            "The reason from the rules engine should be on screen"
        )
        XCTAssertTrue(app.staticTexts["If you would like, decaf or a smaller cup is an easy swap."].exists)

        // 4. Log it.
        tap(element("result.confirm"))
        XCTAssertTrue(element("logged.confirmation").waitForExistence(timeout: 10))
        tap(element("logged.done"))

        // 5. Bring the check-in forward and answer it.
        let simulate = element("home.simulateCheckIn")
        XCTAssertTrue(simulate.waitForExistence(timeout: 10), "The check-in shortcut should be offered")
        tap(simulate)

        let pending = element("home.pendingCheckIn")
        XCTAssertTrue(pending.waitForExistence(timeout: 10), "A pending check-in should appear")
        tap(pending)

        XCTAssertTrue(app.staticTexts["How are you feeling after your meal?"].waitForExistence(timeout: 10))
        tap(element("checkin.severity.mild"))
        tap(element("checkin.symptom.heartburn"))
        tap(element("checkin.save"))

        // 6. Find it in the history, with what was felt.
        let history = element("home.history")
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        tap(history)

        XCTAssertTrue(app.staticTexts["Black tea"].waitForExistence(timeout: 10), "The meal should be in history")
        tap(app.staticTexts["Black tea"])

        // Rows are combined into single elements so VoiceOver reads them as one
        // phrase, so assert on the element's label rather than on loose text.
        let severity = element("detail.severity")
        XCTAssertTrue(severity.waitForExistence(timeout: 10), "The meal detail should open")
        XCTAssertTrue(severity.label.contains("Mild"), "The check-in answer should be recorded: \(severity.label)")

        let symptoms = element("detail.symptoms")
        XCTAssertTrue(symptoms.waitForExistence(timeout: 5))
        XCTAssertTrue(
            symptoms.label.contains("Heartburn or reflux"),
            "The symptom should be recorded: \(symptoms.label)"
        )

        // The note that was shown at the time is kept with the meal.
        XCTAssertTrue(app.staticTexts["Notes shown at the time"].exists)
    }

    func testUnreadablePhotoFallsBackToTypingWithNoNote() throws {
        tap(element("home.scanButton"))
        tap(element("capture.fixture.malformedResponse"))

        let field = element("manual.name")
        XCTAssertTrue(field.waitForExistence(timeout: 15), "Typing should be offered when the photo cannot be read")
        XCTAssertFalse(app.staticTexts["Heads up"].exists, "No note should be shown when nothing was established")

        field.tap()
        field.typeText("Leftover curry")
        tap(element("manual.confirm"))

        XCTAssertTrue(element("logged.confirmation").waitForExistence(timeout: 10))
        tap(element("logged.done"))

        tap(element("home.history"))
        XCTAssertTrue(app.staticTexts["Leftover curry"].waitForExistence(timeout: 10))
    }

    /// A correction is the highest-trust thing the app has, and the only way she
    /// can overrule a wrong guess. Removing the ingredient a note came from must
    /// take the note with it.
    func testCorrectingIngredientsRemovesTheNoteItProduced() throws {
        tap(element("home.scanButton"))
        tap(element("capture.fixture.caffeinatedTea"))

        let yes = element("clarify.yes")
        XCTAssertTrue(yes.waitForExistence(timeout: 15), "The clarification question should appear")
        tap(yes)

        XCTAssertTrue(element("result.itemName").waitForExistence(timeout: 10), "The result should appear")
        XCTAssertTrue(app.staticTexts["Heads up"].exists, "The caffeine note should be shown before correcting")

        // It was decaf after all.
        tap(element("result.correct"))

        let caffeine = element("correct.category.caffeine")
        XCTAssertTrue(caffeine.waitForExistence(timeout: 10), "The correction sheet should list the ingredients")
        tap(caffeine)
        tap(element("correct.save"))

        XCTAssertTrue(element("result.itemName").waitForExistence(timeout: 10), "The result should come back")
        XCTAssertFalse(
            app.staticTexts["Heads up"].exists,
            "Removing caffeine should remove the note it produced"
        )
    }

    // MARK: - Helpers

    /// Identifiers are attached to a mix of buttons, cells and containers
    /// depending on how SwiftUI renders each one, so match on any element type.
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Scrolls the element into view if it is off screen, then taps it.
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "\(element) never appeared", file: file, line: line)

        var attempts = 0
        while !element.isHittable && attempts < 4 {
            app.swipeUp()
            attempts += 1
        }
        element.tap()
    }
}
