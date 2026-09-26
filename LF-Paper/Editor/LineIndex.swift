//
//  LineIndex.swift
//  LF-Paper
//

import Foundation

/// Where each line starts, for turning character positions into line numbers.
/// Lines end at "\n", so "\r\n" counts as a single line break.
nonisolated struct LineIndex: Sendable {
    /// UTF-16 offset of the first character of each line. Always starts with 0.
    let lineStarts: [Int]

    init(text: NSString) {
        var starts = [0]
        var searchRange = NSRange(location: 0, length: text.length)
        while true {
            let newline = text.range(of: "\n", options: .literal, range: searchRange)
            guard newline.location != NSNotFound else { break }
            let nextLineStart = NSMaxRange(newline)
            starts.append(nextLineStart)
            searchRange = NSRange(location: nextLineStart, length: text.length - nextLineStart)
        }
        lineStarts = starts
    }

    var lineCount: Int { lineStarts.count }

    /// The 1-based line containing the character at `characterIndex`.
    func lineNumber(at characterIndex: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lineStarts[middle] <= characterIndex {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low + 1
    }
}
