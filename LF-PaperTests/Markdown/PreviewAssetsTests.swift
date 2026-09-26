//
//  PreviewAssetsTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

struct PreviewAssetsTests {
    private let root = URL(filePath: "/Users/me/Notes", directoryHint: .isDirectory)

    private func assetURL(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    @Test func baseURLPointsAtTheFolderThroughTheAssetScheme() {
        let base = PreviewAssets.baseURL(for: root.appending(path: "My Docs", directoryHint: .isDirectory))

        #expect(base.absoluteString == "lfpaper-asset://local/Users/me/Notes/My%20Docs/")
    }

    @Test func relativeImagesResolveInsideTheWorkspace() throws {
        let base = PreviewAssets.baseURL(for: root.appending(path: "docs", directoryHint: .isDirectory))
        let image = try #require(URL(string: "img/logo.png", relativeTo: base))

        let file = PreviewAssets.fileURL(for: image.absoluteURL, within: root)

        #expect(file?.path(percentEncoded: false) == "/Users/me/Notes/docs/img/logo.png")
    }

    @Test func filesOutsideTheWorkspaceAreRefused() throws {
        #expect(PreviewAssets.fileURL(for: try assetURL("lfpaper-asset://local/etc/passwd"), within: root) == nil)
        #expect(PreviewAssets.fileURL(for: try assetURL("lfpaper-asset://local/Users/me/Notes/../secret.png"), within: root) == nil)
        #expect(PreviewAssets.fileURL(for: try assetURL("lfpaper-asset://local/Users/me/NotesOther/a.png"), within: root) == nil)
    }

    @Test func theWorkspaceFolderItselfIsNotAnAsset() throws {
        #expect(PreviewAssets.fileURL(for: try assetURL("lfpaper-asset://local/Users/me/Notes/"), within: root) == nil)
    }

    @Test func otherSchemesAndHostsAreRefused() throws {
        #expect(PreviewAssets.fileURL(for: try assetURL("file:///Users/me/Notes/a.png"), within: root) == nil)
        #expect(PreviewAssets.fileURL(for: try assetURL("lfpaper-asset://elsewhere/Users/me/Notes/a.png"), within: root) == nil)
    }

    @Test func symlinksLeavingTheWorkspaceAreRefused() throws {
        let workspace = try TemporaryDirectory()
        let outside = try TemporaryDirectory()
        let secret = try outside.makeFile("secret.png", contents: "x")
        let link = workspace.url.appending(path: "link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)

        let request = PreviewAssets.baseURL(for: workspace.url).appending(path: "link.png")

        #expect(PreviewAssets.fileURL(for: request, within: workspace.url) == nil)
    }

    @Test func mimeTypesComeFromTheFileExtension() {
        #expect(PreviewAssets.mimeType(for: URL(filePath: "/a/b.png")) == "image/png")
        #expect(PreviewAssets.mimeType(for: URL(filePath: "/a/b.svg")) == "image/svg+xml")
        #expect(PreviewAssets.mimeType(for: URL(filePath: "/a/b.unknownext")) == "application/octet-stream")
    }
}
