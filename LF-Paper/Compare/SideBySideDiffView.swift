//
//  SideBySideDiffView.swift
//  LF-Paper
//

import SwiftUI

/// Old document on the left, new on the right (see `DiffSplitView`). Each side scrolls sideways on
/// its own; scrolling up or down moves both. The focused change gets an accent bar and is scrolled into view.
struct SideBySideDiffView: NSViewRepresentable {
    let rows: [SideBySideRow]
    let changeStarts: [Int]
    let focusedChange: Int?
    /// Measured with the comparison; measured here when not given.
    var longestLines: DiffLayout.LongestLines?

    final class Coordinator {
        var rows: [SideBySideRow]?
        var focusedChange: Int?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> DiffSplitView {
        DiffSplitView(frame: .zero)
    }

    func updateNSView(_ view: DiffSplitView, context: Context) {
        let coordinator = context.coordinator
        let focusedRows = SideBySideRows.rows(ofChange: focusedChange, in: rows, changeStarts: changeStarts)
        if coordinator.rows != rows {
            coordinator.rows = rows
            view.show(rows: rows, longestLines: longestLines ?? DiffLayout.longestLines(in: rows), focusedRows: focusedRows)
        } else {
            view.setFocusedRows(focusedRows)
        }
        if focusedChange != coordinator.focusedChange {
            coordinator.focusedChange = focusedChange
            if let row = focusedRows?.lowerBound {
                view.scrollToRow(row)
            }
        }
    }
}
