//
//  UnsavedChangesPrompt.swift
//  LF-Paper
//

import Foundation

/// Wording shared by the in-window prompt and the quit alert, following the standard macOS phrasing.
enum UnsavedChangesPrompt {
    static let informativeText = "Your changes will be lost if you don’t save them."
    static let saveTitle = "Save"
    static let discardTitle = "Don’t Save"
    static let cancelTitle = "Cancel"

    static func message(fileName: String) -> String {
        "Do you want to save the changes you made to “\(fileName)”?"
    }

    static func message(windowCount: Int) -> String {
        "You have unsaved changes in \(windowCount) windows. Do you want to save them?"
    }
}
