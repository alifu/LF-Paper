//
//  PanelSearchField.swift
//  LF-Paper
//

import AppKit
import SwiftUI

/// A one-line text field for search panels. ↑ and ↓ move through the results, Return picks one
/// and Esc closes, while the text keeps keyboard focus (SwiftUI's TextField doesn't pass these on).
struct PanelSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    /// Changing this moves keyboard focus into the field.
    var focusRequest: UUID?
    var onMove: (Int) -> Void = { _ in }
    var onSubmit: () -> Void = {}
    var onCancel: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: { text = $0 }, onMove: onMove, onSubmit: onSubmit, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: NSFont.systemFontSize + 2)
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.setAccessibilityLabel(placeholder)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTextChange = { text = $0 }
        coordinator.onMove = onMove
        coordinator.onSubmit = onSubmit
        coordinator.onCancel = onCancel
        if field.stringValue != text {
            field.stringValue = text
        }
        if let focusRequest, focusRequest != coordinator.lastFocusRequest {
            coordinator.lastFocusRequest = focusRequest
            // After this update, once the field is in its window.
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var onTextChange: (String) -> Void
        var onMove: (Int) -> Void
        var onSubmit: () -> Void
        var onCancel: () -> Void
        var lastFocusRequest: UUID?

        init(
            onTextChange: @escaping (String) -> Void,
            onMove: @escaping (Int) -> Void,
            onSubmit: @escaping () -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onTextChange = onTextChange
            self.onMove = onMove
            self.onSubmit = onSubmit
            self.onCancel = onCancel
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            onTextChange(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                onMove(-1)
            case #selector(NSResponder.moveDown(_:)):
                onMove(1)
            case #selector(NSResponder.insertNewline(_:)):
                onSubmit()
            case #selector(NSResponder.cancelOperation(_:)):
                onCancel()
            default:
                return false
            }
            return true
        }
    }
}
