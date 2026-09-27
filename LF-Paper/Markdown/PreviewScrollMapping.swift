//
//  PreviewScrollMapping.swift
//  LF-Paper
//

import Foundation

/// Where a block of the rendered Markdown starts: its first source line and its offset from the
/// top of the page, in points.
nonisolated struct PreviewAnchor: Equatable, Sendable {
    let line: Int
    let offset: Double
}

/// Converts between editor lines and preview scroll offsets, so the two scroll together.
/// Between two blocks the position is interpolated, so long paragraphs scroll smoothly.
nonisolated enum PreviewScrollMapping {
    /// Sorted by line, keeping only blocks that start further down in both the source and the page.
    /// Nested blocks (a list item on its list's line) and oddly placed ones are dropped.
    static func normalized(_ anchors: [PreviewAnchor]) -> [PreviewAnchor] {
        anchors
            .sorted { ($0.line, $0.offset) < ($1.line, $1.offset) }
            .reduce(into: []) { kept, anchor in
                guard let last = kept.last else {
                    kept.append(anchor)
                    return
                }
                if anchor.line > last.line && anchor.offset > last.offset {
                    kept.append(anchor)
                }
            }
    }

    /// The preview offset for a (fractional, 1-based) source line. `anchors` must be normalized.
    static func offset(forLine line: Double, anchors: [PreviewAnchor]) -> Double {
        interpolate(line, anchors: anchors, from: { Double($0.line) }, to: \.offset, empty: 0)
    }

    /// The (fractional, 1-based) source line for a preview offset. `anchors` must be normalized.
    static func line(forOffset offset: Double, anchors: [PreviewAnchor]) -> Double {
        interpolate(offset, anchors: anchors, from: \.offset, to: { Double($0.line) }, empty: 1)
    }

    private static func interpolate(
        _ value: Double,
        anchors: [PreviewAnchor],
        from source: (PreviewAnchor) -> Double,
        to target: (PreviewAnchor) -> Double,
        empty: Double
    ) -> Double {
        guard let first = anchors.first, let last = anchors.last else { return empty }
        if value <= source(first) { return target(first) }
        if value >= source(last) { return target(last) }
        for (start, end) in zip(anchors, anchors.dropFirst()) where source(start) <= value && value < source(end) {
            let fraction = (value - source(start)) / (source(end) - source(start))
            return target(start) + fraction * (target(end) - target(start))
        }
        return target(last)
    }
}
