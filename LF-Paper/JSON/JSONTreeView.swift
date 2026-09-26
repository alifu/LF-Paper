//
//  JSONTreeView.swift
//  LF-Paper
//

import SwiftUI

/// SwiftUI host for the JSON outline. The controller lives as long as the view.
struct JSONTreeView: NSViewRepresentable {
    let root: JSONTreeNode?
    /// Changes whenever the document was re-parsed; the outline only reloads then.
    let version: Int
    let visiblePaths: Set<JSONPath>?
    let onSelect: (JSONPath) -> Void

    func makeCoordinator() -> JSONOutlineController {
        JSONOutlineController()
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.show(root: root, version: version, visiblePaths: visiblePaths)
    }
}
