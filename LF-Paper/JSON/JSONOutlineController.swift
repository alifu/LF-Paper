//
//  JSONOutlineController.swift
//  LF-Paper
//

import AppKit

/// One row of the JSON tree. Children are created when first needed and respect the current filter.
final class JSONOutlineItem: NSObject {
    let node: JSONTreeNode
    private let visiblePaths: Set<JSONPath>?

    private(set) lazy var children: [JSONOutlineItem] = (node.children ?? [])
        .filter { visiblePaths?.contains($0.path) ?? true }
        .map { JSONOutlineItem(node: $0, visiblePaths: visiblePaths) }

    init(node: JSONTreeNode, visiblePaths: Set<JSONPath>?) {
        self.node = node
        self.visiblePaths = visiblePaths
    }

    var isExpandable: Bool {
        visiblePaths == nil ? node.isExpandable : !children.isEmpty
    }
}

/// The JSON tree: an `NSOutlineView` that loads rows lazily (fast for huge documents), keeps
/// expanded rows and the selection across re-parses, filters, and copies paths, keys and values.
final class JSONOutlineController: NSObject {
    enum CopyPart: Int {
        case path, key, value
    }

    private static let columnID = NSUserInterfaceItemIdentifier("JSONTreeColumn")
    private static let cellID = NSUserInterfaceItemIdentifier("JSONTreeCell")
    private static let rowHeight: CGFloat = 22

    let scrollView = NSScrollView()
    let outlineView = NSOutlineView()
    /// Called when the user selects a row (not when a reload restores the selection).
    var onSelect: ((JSONPath) -> Void)?
    var pasteboard = NSPasteboard.general

    private var root: JSONOutlineItem?
    private var shownVersion: Int?
    private var shownVisiblePaths: Set<JSONPath>?
    private var isReloading = false

    override init() {
        super.init()
        let column = NSTableColumn(identifier: Self.columnID)
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.setAccessibilityIdentifier("json-tree")
        outlineView.style = .plain
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outlineView.rowHeight = Self.rowHeight
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.menu = makeMenu()

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
    }

    /// Shows a tree. Does nothing unless the parse `version` or the filter changed.
    func show(root node: JSONTreeNode?, version: Int, visiblePaths: Set<JSONPath>?) {
        guard version != shownVersion || visiblePaths != shownVisiblePaths else { return }
        let expanded = expandedPaths()
        let selected = selectedPath()
        shownVersion = version
        shownVisiblePaths = visiblePaths
        root = node.map { JSONOutlineItem(node: $0, visiblePaths: visiblePaths) }

        isReloading = true
        defer { isReloading = false }
        outlineView.reloadData()
        guard let root else { return }
        if visiblePaths != nil {
            outlineView.expandItem(root, expandChildren: true) // only matches are loaded, so this is small
        } else if expanded.isEmpty {
            outlineView.expandItem(root)
        } else {
            restoreExpansion(of: expanded)
        }
        if let selected, let item = item(at: selected) {
            let row = outlineView.row(forItem: item)
            if row >= 0 {
                outlineView.selectRowIndexes([row], byExtendingSelection: false)
            }
        }
    }

    func copy(_ part: CopyPart, row: Int) {
        guard let node = (outlineView.item(atRow: row) as? JSONOutlineItem)?.node else { return }
        let text = switch part {
        case .path: node.path.description
        case .key: node.title
        case .value: Self.copyableText(of: node.value)
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Strings without quotes, numbers as written, containers pretty-printed.
    private static func copyableText(of value: JSONValue) -> String {
        switch value {
        case .string(let text): text
        case .number(let number): number.literal
        case .object, .array: JSONFormatter.pretty(value)
        case .bool, .null: JSONFormatter.minified(value)
        }
    }

    // MARK: Expansion and selection by path

    private func expandedPaths() -> Set<JSONPath> {
        Set((0..<outlineView.numberOfRows).compactMap { row in
            let item = outlineView.item(atRow: row)
            return outlineView.isItemExpanded(item) ? (item as? JSONOutlineItem)?.node.path : nil
        })
    }

    private func restoreExpansion(of paths: Set<JSONPath>) {
        // Parents first, so each item is visible by the time it's expanded.
        for path in paths.sorted(by: { $0.components.count < $1.components.count }) {
            if let item = item(at: path) {
                outlineView.expandItem(item)
            }
        }
    }

    private func selectedPath() -> JSONPath? {
        (outlineView.item(atRow: outlineView.selectedRow) as? JSONOutlineItem)?.node.path
    }

    private func item(at path: JSONPath) -> JSONOutlineItem? {
        var current = root
        for component in path.components {
            current = current?.children.first { $0.node.path.components.last == component }
        }
        return current
    }

    // MARK: Context menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let entries: [(String, CopyPart)] = [("Copy Path", .path), ("Copy Key", .key), ("Copy Value", .value)]
        for (title, part) in entries {
            let item = NSMenuItem(title: title, action: #selector(copyFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.tag = part.rawValue
            menu.addItem(item)
        }
        return menu
    }

    @objc private func copyFromMenu(_ sender: NSMenuItem) {
        guard let part = CopyPart(rawValue: sender.tag) else { return }
        copy(part, row: outlineView.clickedRow)
    }
}

extension JSONOutlineController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item = item as? JSONOutlineItem else { return root == nil ? 0 : 1 }
        return item.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let item = item as? JSONOutlineItem {
            return item.children[index]
        }
        guard let root else { preconditionFailure("The outline asked for a root row while none is shown") }
        return root
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? JSONOutlineItem)?.isExpandable ?? false
    }
}

extension JSONOutlineController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? JSONOutlineItem else { return nil }
        let cell = outlineView.makeView(withIdentifier: Self.cellID, owner: self) as? JSONOutlineCellView
            ?? JSONOutlineCellView(identifier: Self.cellID)
        cell.configure(with: item.node)
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isReloading, let path = selectedPath() else { return }
        onSelect?(path)
    }
}

/// Icon, key and value summary for one row. Uses standard text fields, so it follows dark mode.
final class JSONOutlineCellView: NSTableCellView {
    private let icon = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let summaryField = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        titleField.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        summaryField.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        summaryField.lineBreakMode = .byTruncatingTail
        summaryField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [icon, titleField, summaryField])
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        imageView = icon
        textField = titleField
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(with node: JSONTreeNode) {
        let style = JSONKindStyle(kind: node.kind)
        icon.image = NSImage(systemSymbolName: style.symbolName, accessibilityDescription: style.name)
        icon.contentTintColor = style.color
        titleField.stringValue = node.title
        summaryField.stringValue = node.summary
        summaryField.textColor = node.isExpandable || node.children != nil ? .secondaryLabelColor : style.color
        setAccessibilityLabel("\(node.title), \(style.name), \(node.summary)")
    }
}

/// Icon and color for each JSON type, shared by the tree rows.
struct JSONKindStyle {
    let symbolName: String
    let name: String
    let color: NSColor

    init(kind: JSONTreeNode.Kind) {
        switch kind {
        case .object: (symbolName, name, color) = ("curlybraces", "object", .systemPurple)
        case .array: (symbolName, name, color) = ("list.number", "array", .systemOrange)
        case .string: (symbolName, name, color) = ("textformat", "string", .systemRed)
        case .number: (symbolName, name, color) = ("number", "number", .systemBlue)
        case .bool: (symbolName, name, color) = ("switch.2", "boolean", .systemPink)
        case .null: (symbolName, name, color) = ("circle.slash", "null", .secondaryLabelColor)
        }
    }
}
