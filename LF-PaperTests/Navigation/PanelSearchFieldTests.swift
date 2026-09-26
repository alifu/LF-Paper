//
//  PanelSearchFieldTests.swift
//  LF-PaperTests
//

import AppKit
import Testing
@testable import LF_Paper

/// The panel search field turns ↑, ↓, Return and Esc into actions and reports typing.
@MainActor
final class PanelSearchFieldTests {
    private var text = ""
    private var moves: [Int] = []
    private var submitCount = 0
    private var cancelCount = 0
    private let field = NSTextField()
    private let fieldEditor = NSTextView()
    private lazy var coordinator = PanelSearchField.Coordinator(
        onTextChange: { [unowned self] in text = $0 },
        onMove: { [unowned self] in moves.append($0) },
        onSubmit: { [unowned self] in submitCount += 1 },
        onCancel: { [unowned self] in cancelCount += 1 }
    )

    private func perform(_ selector: Selector) -> Bool {
        coordinator.control(field, textView: fieldEditor, doCommandBy: selector)
    }

    @Test func arrowsMoveTheSelection() {
        #expect(perform(#selector(NSResponder.moveDown(_:))))
        #expect(perform(#selector(NSResponder.moveUp(_:))))

        #expect(moves == [1, -1])
    }

    @Test func returnSubmitsAndEscapeCancels() {
        #expect(perform(#selector(NSResponder.insertNewline(_:))))
        #expect(perform(#selector(NSResponder.cancelOperation(_:))))

        #expect(submitCount == 1)
        #expect(cancelCount == 1)
    }

    @Test func otherKeysAreLeftToTheTextField() {
        #expect(!perform(#selector(NSResponder.moveLeft(_:))))
        #expect(!perform(#selector(NSResponder.deleteBackward(_:))))
        #expect(moves.isEmpty)
    }

    @Test func typingReportsTheText() {
        field.stringValue = "readme"

        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))

        #expect(text == "readme")
    }

    @Test func selectionMovesWithinTheResults() {
        #expect(QuickOpenPanel.movedSelection(0, by: 1, count: 3) == 1)
        #expect(QuickOpenPanel.movedSelection(2, by: 1, count: 3) == 2)
        #expect(QuickOpenPanel.movedSelection(0, by: -1, count: 3) == 0)
        #expect(QuickOpenPanel.movedSelection(5, by: 0, count: 0) == 0)
    }
}
