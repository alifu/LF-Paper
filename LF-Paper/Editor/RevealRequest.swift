//
//  RevealRequest.swift
//  LF-Paper
//

import Foundation

/// A one-off request for the editor to select a range and scroll to it.
/// Each request has its own identity, so asking for the same range twice still moves the cursor.
nonisolated struct RevealRequest: Equatable, Sendable {
    let id = UUID()
    let range: NSRange
    /// Move keyboard focus to the editor (e.g. to fix an error); tree browsing keeps focus in the tree.
    let focusesEditor: Bool
    /// Flash the range like Find does; off when quietly putting back a remembered selection.
    var highlights = true
}
