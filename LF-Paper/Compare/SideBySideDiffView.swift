//
//  SideBySideDiffView.swift
//  LF-Paper
//

import SwiftUI

/// Old document on the left, new on the right, with removed lines red and added lines green.
/// The focused change gets an accent bar and is scrolled into view.
struct SideBySideDiffView: View {
    let rows: [SideBySideRow]
    let changeStarts: [Int]
    let focusedChange: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        DiffRowView(row: row, isFocused: focusedRows?.contains(row.id) ?? false)
                            .id(row.id)
                    }
                }
            }
            .onChange(of: focusedChange) { _, change in
                guard let change, changeStarts.indices.contains(change) else { return }
                withAnimation {
                    proxy.scrollTo(changeStarts[change], anchor: .center)
                }
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .background(Color(nsColor: .textBackgroundColor))
    }

    /// All rows of the focused block of changes.
    private var focusedRows: Range<Int>? {
        guard let focusedChange, changeStarts.indices.contains(focusedChange) else { return nil }
        let start = changeStarts[focusedChange]
        var end = start
        while end < rows.count, rows[end].isChange {
            end += 1
        }
        return start..<end
    }
}

private struct DiffRowView: View {
    let row: SideBySideRow
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            DiffCellView(cell: row.left)
            Divider()
            DiffCellView(cell: row.right)
        }
        .overlay(alignment: .leading) {
            if isFocused {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
            }
        }
    }
}

private struct DiffCellView: View {
    private static let lineNumberWidth: CGFloat = 40

    let cell: DiffCell?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(cell.map { String($0.lineNumber) } ?? "")
                .foregroundStyle(.tertiary)
                .frame(width: Self.lineNumberWidth, alignment: .trailing)
            Text(verbatim: cell?.text ?? "")
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(background)
    }

    private var background: Color {
        switch cell?.kind {
        case .removed: .red.opacity(0.18)
        case .added: .green.opacity(0.18)
        case .same: .clear
        case nil: .gray.opacity(0.08) // this side has no line here
        }
    }
}
