//
//  WindowCloseGuard.swift
//  LF-Paper
//

import AppKit

/// Asks about unsaved changes before a workspace window closes (SwiftUI can't cancel a close).
///
/// It takes the window's delegate slot and forwards every other message to the delegate that was
/// there, which is SwiftUI's, so the rest of the window keeps working as before.
final class WindowCloseGuard: NSObject, NSWindowDelegate {
    typealias Answer = @MainActor (WorkspaceModel.UnsavedChangesDecision) -> Void
    /// Shows the question for these files and calls back with the answer.
    typealias Ask = @MainActor (NSWindow, [OpenDocument], @escaping Answer) -> Void

    private weak var model: WorkspaceModel?
    private let behavior: () -> UnsavedChangesOnClose
    private let ask: Ask
    /// Held strongly: a window only holds its delegate weakly, and this replaces SwiftUI's in that slot.
    /// `nonisolated(unsafe)` because AppKit asks `responds(to:)` without actor isolation; it is only
    /// ever set in `attach(to:)` on the main thread, where AppKit also sends window-delegate messages.
    nonisolated(unsafe) private(set) var originalDelegate: (any NSWindowDelegate)?

    init(
        model: WorkspaceModel,
        behavior: @escaping () -> UnsavedChangesOnClose = { UnsavedChangesOnClose.current() },
        ask: @escaping Ask = WindowCloseGuard.askWithSheet
    ) {
        self.model = model
        self.behavior = behavior
        self.ask = ask
    }

    /// Safe to call repeatedly, for example whenever SwiftUI might have replaced the delegate.
    func attach(to window: NSWindow) {
        guard window.delegate !== self else { return }
        originalDelegate = window.delegate
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard originalDelegate?.windowShouldClose?(sender) ?? true else { return false }
        guard let model, model.hasUnsavedChanges else { return true }

        switch behavior() {
        case .saveAutomatically:
            return model.saveAll()
        case .ask:
            ask(sender, model.unsavedDocuments) { [weak model, weak sender] decision in
                guard let model, let sender, decision.apply(to: [model]) else { return }
                sender.close() // doesn't ask again: close() skips windowShouldClose
            }
            return false
        }
    }

    // MARK: Forwarding

    nonisolated override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (originalDelegate?.responds(to: selector) ?? false)
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        originalDelegate?.responds(to: selector) == true ? originalDelegate : super.forwardingTarget(for: selector)
    }

    // MARK: Asking

    /// Save / Don't Save / Cancel as a sheet on the window, in the standard macOS wording.
    static func askWithSheet(window: NSWindow, documents: [OpenDocument], answer: @escaping Answer) {
        let alert = NSAlert()
        alert.messageText = UnsavedChangesPrompt.message(for: documents)
        alert.informativeText = UnsavedChangesPrompt.informativeText
        alert.addButton(withTitle: UnsavedChangesPrompt.saveTitle)
        alert.addButton(withTitle: UnsavedChangesPrompt.discardTitle)
        alert.addButton(withTitle: UnsavedChangesPrompt.cancelTitle)
        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn: answer(.save)
            case .alertSecondButtonReturn: answer(.discard)
            default: answer(.cancel)
            }
        }
    }
}
