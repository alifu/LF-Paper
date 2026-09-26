//
//  PreviewNavigationPolicyTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

struct PreviewNavigationPolicyTests {
    private let page = PreviewAssets.baseURL(for: URL(filePath: "/Users/me/Notes", directoryHint: .isDirectory))

    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    @Test func thePageItselfMayLoad() {
        #expect(PreviewNavigationPolicy.decide(url: page, isLinkClick: false, pageURL: page) == .allow)
    }

    @Test(arguments: ["https://example.com/a", "http://example.com", "mailto:me@example.com"])
    func webAndMailLinksOpenOutsideTheApp(link: String) throws {
        let target = try url(link)

        #expect(PreviewNavigationPolicy.decide(url: target, isLinkClick: true, pageURL: page) == .openExternally(target))
    }

    @Test func inPageAnchorsStayInThePreview() throws {
        let anchor = try url(page.absoluteString + "#section")

        #expect(PreviewNavigationPolicy.decide(url: anchor, isLinkClick: true, pageURL: page) == .allow)
    }

    @Test(arguments: ["file:///etc/passwd", "javascript:alert(1)", "lfpaper-asset://local/Users/me/Notes/other.md"])
    func otherLinksAreBlocked(link: String) throws {
        #expect(PreviewNavigationPolicy.decide(url: try url(link), isLinkClick: true, pageURL: page) == .deny)
    }

    @Test func navigationsThePageStartsOnItsOwnAreBlocked() throws {
        // e.g. <meta http-equiv="refresh"> or a form submission
        #expect(PreviewNavigationPolicy.decide(url: try url("https://evil.example"), isLinkClick: false, pageURL: page) == .deny)
    }

    @Test func missingURLIsBlocked() {
        #expect(PreviewNavigationPolicy.decide(url: nil, isLinkClick: true, pageURL: page) == .deny)
    }
}
