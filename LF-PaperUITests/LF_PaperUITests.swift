//
//  LF_PaperUITests.swift
//  LF-PaperUITests
//
//  Created by Alif Ramadhoni on 26/09/26.
//

import AppKit
import XCTest

/// The main flows, end to end. The app opens a fresh folder of sample files
/// (README.md, data.json, other.json) when launched with `-UITestFixture YES`.
final class LF_PaperUITests: XCTestCase {
    private static let timeout: TimeInterval = 10
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestFixture", "YES", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: Helpers

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @discardableResult
    private func waitFor(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let found = element(identifier)
        XCTAssertTrue(found.waitForExistence(timeout: Self.timeout), "\(identifier) did not appear", file: file, line: line)
        return found
    }

    private func openFile(_ name: String) {
        waitFor("file-\(name)").click()
        waitFor("tab-\(name)")
    }

    private func editorText() -> String {
        waitFor("editor").value as? String ?? ""
    }

    private func chooseMenuItem(_ item: String, inMenu menu: String) {
        app.menuBars.menuBarItems[menu].click()
        app.menuBars.menuItems[item].click()
    }

    private func waitUntil(_ description: String, _ condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: Self.timeout), .completed, description)
    }

    // MARK: Flows

    @MainActor
    func testEditAndSaveMarkdown() throws {
        openFile("README.md")
        XCTAssertTrue(editorText().hasPrefix("# Fixture"))

        let editor = waitFor("editor")
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command) // end of the document
        editor.typeText("More text.")
        let tab = waitFor("tab-README.md")
        waitUntil("the tab shows unsaved changes") { tab.label == "README.md, edited" }

        editor.typeKey("s", modifierFlags: .command)
        waitUntil("saving clears the edited mark") { tab.label == "README.md" }
        XCTAssertTrue(editorText().hasSuffix("More text."))
    }

    @MainActor
    func testJSONTreeAndFormat() throws {
        openFile("data.json")
        let tree = waitFor("json-tree")
        waitUntil("the tree shows the document") { tree.outlineRows.count > 0 }

        chooseMenuItem("Format", inMenu: "JSON")

        waitUntil("Format pretty-prints the JSON") { self.editorText().contains("\n  \"name\": \"Ada\",") }
        XCTAssertEqual(waitFor("tab-data.json").label, "data.json, edited")
    }

    @MainActor
    func testTabsOpenAndClose() throws {
        openFile("README.md")
        openFile("data.json")
        XCTAssertTrue(element("tab-README.md").exists)

        app.typeKey("w", modifierFlags: .command)

        waitUntil("⌘W closes the active tab") { !self.element("tab-data.json").exists }
        XCTAssertTrue(element("tab-README.md").exists)
        XCTAssertTrue(editorText().hasPrefix("# Fixture"))
    }

    @MainActor
    func testScratchpadKeepsItsTextAndCopiesIt() throws {
        openFile("README.md")
        app.typeKey("e", modifierFlags: [.command, .shift])
        let scratchTab = waitFor("tab-Scratch")
        waitUntil("⇧⌘E shows the scratchpad") { self.editorText().isEmpty }

        let editor = waitFor("editor")
        editor.click()
        editor.typeText("Summarize this file.")
        XCTAssertEqual(scratchTab.label, "Scratch") // never marked as edited
        app.typeKey("c", modifierFlags: [.command, .option, .shift])
        waitUntil("Copy All puts the text on the pasteboard") {
            NSPasteboard.general.string(forType: .string) == "Summarize this file."
        }

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(scratchTab.exists, "⌘W doesn't close the Scratch tab")

        waitFor("tab-README.md").click()
        waitUntil("the file tab shows its file") { self.editorText().hasPrefix("# Fixture") }
        scratchTab.click()
        waitUntil("the scratchpad kept its text") { self.editorText() == "Summarize this file." }
    }

    @MainActor
    func testQuickOpenOpensAFileByName() throws {
        waitFor("file-README.md")
        app.typeKey("p", modifierFlags: .command)
        let field = waitFor("quick-open-field")

        field.typeText("oth")
        field.typeKey(.return, modifierFlags: [])

        waitFor("tab-other.json")
        XCTAssertFalse(element("quick-open-field").exists, "Quick Open closes after opening a file")
    }

    @MainActor
    func testFindInFolderOpensTheMatch() throws {
        waitFor("file-README.md")
        app.typeKey("f", modifierFlags: [.command, .shift])
        let field = waitFor("folder-search-field")

        field.typeText("Grace")
        field.typeKey(.return, modifierFlags: [])
        let summary = waitFor("folder-search-summary")
        waitUntil("the search finds one match") { (summary.value as? String ?? summary.label) == "1 match in 1 file" }

        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Line 1:'")).firstMatch.click()
        waitFor("tab-other.json")
    }

    @MainActor
    func testClosingAWindowWithUnsavedChangesAsksFirst() throws {
        openFile("README.md")
        let editor = waitFor("editor")
        editor.click()
        editor.typeText("Unsaved.")

        app.windows.firstMatch.buttons[XCUIIdentifierCloseWindow].click()
        let cancel = app.sheets.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: Self.timeout), "closing asks about unsaved changes")
        cancel.click()

        XCTAssertTrue(waitFor("tab-README.md").exists, "Cancel keeps the window open")
        XCTAssertEqual(waitFor("tab-README.md").label, "README.md, edited")
    }

    @MainActor
    func testCompareWithSavedVersionShowsTheEdit() throws {
        openFile("README.md")
        let editor = waitFor("editor")
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("An unsaved line.")

        chooseMenuItem("Compare with Saved Version", inMenu: "File")

        let counter = waitFor("change-counter")
        waitUntil("the edit shows as one change") { (counter.value as? String ?? counter.label) == "1 change" }
    }

    @MainActor
    func testOutlineListsTheHeadings() throws {
        openFile("README.md")
        app.radioButtons["Outline"].click()

        let heading = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Heading level 1: Fixture'")).firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: Self.timeout), "the README's heading is listed")
        heading.click()
        XCTAssertTrue(editorText().hasPrefix("# Fixture"))
    }

    @MainActor
    func testCompareTwoFiles() throws {
        waitFor("file-data.json").rightClick()
        app.menuItems["Compare as Left"].click()
        app.windows.firstMatch.typeKey("`", modifierFlags: .command) // back to the workspace window
        waitFor("file-other.json").rightClick()
        app.menuItems["Compare as Right"].click()

        let counter = waitFor("change-counter")
        waitUntil("the files are compared") { (counter.value as? String ?? counter.label).contains("change") }

        app.typeKey(.downArrow, modifierFlags: [.command, .option])
        waitUntil("the first change is focused") { (counter.value as? String ?? counter.label).hasPrefix("1 of") }
    }
}
