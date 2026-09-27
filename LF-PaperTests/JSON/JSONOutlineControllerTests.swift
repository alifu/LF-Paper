//
//  JSONOutlineControllerTests.swift
//  LF-PaperTests
//

import AppKit
import Testing
@testable import LF_Paper

/// Drives the real NSOutlineView offscreen: rows, filtering, expansion, selection, copying and pixels.
@MainActor
final class JSONOutlineControllerTests {
    private static let size = NSSize(width: 400, height: 300)
    private static let sample = #"{"user":{"name":"Ada","age":36},"tags":["math","code"],"active":true}"#

    private let controller = JSONOutlineController()
    private let window: NSWindow
    private let pasteboardName = NSPasteboard.Name("LFPaperTests-\(UUID().uuidString)")
    private let pasteboard: NSPasteboard
    private let root: JSONTreeNode

    init() throws {
        window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = controller.scrollView
        pasteboard = NSPasteboard(name: pasteboardName)
        controller.pasteboard = pasteboard
        root = JSONTreeNode(root: try JSONParser.parse(Self.sample).value)
    }

    deinit {
        // deinit is nonisolated, so look the pasteboard up again by its (Sendable) name.
        NSPasteboard(name: pasteboardName).releaseGlobally()
    }

    private var outline: NSOutlineView { controller.outlineView }

    private var rowTitles: [String] {
        (0..<outline.numberOfRows).compactMap { (outline.item(atRow: $0) as? JSONOutlineItem)?.node.title }
    }

    private func row(of path: String) -> Int? {
        (0..<outline.numberOfRows).first { (outline.item(atRow: $0) as? JSONOutlineItem)?.node.path.description == path }
    }

    @Test func showsTheRootExpanded() {
        controller.show(root: root, version: 1, visiblePaths: nil)

        #expect(rowTitles == ["root", "user", "tags", "active"])
    }

    @Test func filteringShowsOnlyMatchesAndExpandsThem() {
        let visible = JSONTreeFilter.visiblePaths(in: root.value, matching: "math")

        controller.show(root: root, version: 1, visiblePaths: visible)

        #expect(rowTitles == ["root", "tags", "[0]"])
    }

    @Test func aHugeQueryResultOpensOnlyTheTopLevel() throws {
        let big = "[" + (0..<3_000).map { #"{"id":\#($0)}"# }.joined(separator: ",") + "]"
        let bigRoot = JSONTreeNode(root: try JSONParser.parse(big).value)
        let everything = try #require(JSONTreeSearch.result(for: "$..*", in: bigRoot.value).visiblePaths)
        #expect(everything.count > JSONOutlineController.autoExpandLimit)

        controller.show(root: bigRoot, version: 1, visiblePaths: everything)

        #expect(outline.numberOfRows == 3_001) // the root and its items, not each item's contents
    }

    @Test func expandedItemsStayExpandedAfterAReparse() throws {
        controller.show(root: root, version: 1, visiblePaths: nil)
        outline.expandItem(outline.item(atRow: try #require(row(of: "$.user"))))
        let reparsed = JSONTreeNode(root: try JSONParser.parse(Self.sample).value)

        controller.show(root: reparsed, version: 2, visiblePaths: nil)

        #expect(rowTitles == ["root", "user", "name", "age", "tags", "active"])
    }

    @Test func selectingARowReportsItsPath() throws {
        var selected: [String] = []
        controller.onSelect = { selected.append($0.description) }
        controller.show(root: root, version: 1, visiblePaths: nil)

        outline.selectRowIndexes([try #require(row(of: "$.tags"))], byExtendingSelection: false)

        #expect(selected == ["$.tags"])
    }

    @Test func reloadingDoesNotReportTheRestoredSelection() throws {
        var selected: [String] = []
        controller.show(root: root, version: 1, visiblePaths: nil)
        outline.selectRowIndexes([try #require(row(of: "$.tags"))], byExtendingSelection: false)
        controller.onSelect = { selected.append($0.description) }

        controller.show(root: JSONTreeNode(root: try JSONParser.parse(Self.sample).value), version: 2, visiblePaths: nil)

        #expect(selected.isEmpty)
        #expect(outline.selectedRow == row(of: "$.tags"))
    }

    @Test func copiesPathsKeysAndValues() throws {
        controller.show(root: root, version: 1, visiblePaths: nil)
        outline.expandItem(outline.item(atRow: try #require(row(of: "$.tags"))))
        let math = try #require(row(of: "$.tags[0]"))
        let user = try #require(row(of: "$.user"))

        controller.copy(.path, row: math)
        #expect(pasteboard.string(forType: .string) == "$.tags[0]")
        controller.copy(.value, row: math)
        #expect(pasteboard.string(forType: .string) == "math")
        controller.copy(.key, row: user)
        #expect(pasteboard.string(forType: .string) == "user")
        controller.copy(.value, row: user)
        #expect(pasteboard.string(forType: .string) == "{\n  \"name\": \"Ada\",\n  \"age\": 36\n}")
    }

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func treeDrawsReadableText(appearanceName: NSAppearance.Name) throws {
        window.appearance = NSAppearance(named: appearanceName)
        let isDark = appearanceName == .darkAqua
        let isText: (CGFloat) -> Bool = { isDark ? $0 > 0.6 : $0 < 0.4 }

        controller.show(root: nil, version: 0, visiblePaths: nil)
        let empty = try render()
        controller.show(root: root, version: 1, visiblePaths: nil)
        let filled = try render()

        Attachment.record(try #require(filled.representation(using: .png, properties: [:])), named: "tree-\(appearanceName.rawValue).png")
        let emptyPixels = PixelCounter.count(in: empty, matching: isText)
        let textPixels = PixelCounter.count(in: filled, matching: isText)
        #expect(textPixels > emptyPixels + 60, "rows should draw visible text (empty: \(emptyPixels), with rows: \(textPixels))")
    }

    private func render() throws -> NSBitmapImageRep {
        let view = controller.scrollView
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }
}
