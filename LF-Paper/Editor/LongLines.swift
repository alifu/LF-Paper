//
//  LongLines.swift
//  LF-Paper
//

import Foundation

/// Finds very long lines, which make highlighting on every keystroke slow (usually minified JSON).
nonisolated enum LongLines {
    /// About 500 KB on one line: past this, typing with highlighting takes tens of milliseconds.
    static let threshold = 500_000

    /// Whether any line has at least `threshold` UTF-16 characters. Stops at the first one.
    static func containsLongLine(_ text: String) -> Bool {
        let string = text as NSString
        guard string.length >= threshold else { return false }
        var lineStart = 0
        while lineStart < string.length {
            let searchRange = NSRange(location: lineStart, length: string.length - lineStart)
            let newline = string.range(of: "\n", options: .literal, range: searchRange)
            let lineEnd = newline.location == NSNotFound ? string.length : newline.location
            if lineEnd - lineStart >= threshold { return true }
            guard newline.location != NSNotFound else { return false }
            lineStart = NSMaxRange(newline)
        }
        return false
    }
}
