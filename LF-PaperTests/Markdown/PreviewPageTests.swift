//
//  PreviewPageTests.swift
//  LF-PaperTests
//

import Testing
@testable import LF_Paper

struct PreviewPageTests {
    private let page = PreviewPage.html(body: "<p>Hello</p>")

    @Test func placesTheBodyInTheContentElement() {
        #expect(page.contains(#"<article id="content" class="markdown-body"><p>Hello</p></article>"#))
    }

    @Test func contentSecurityPolicyAllowsNoScriptsFramesOrConnections() {
        #expect(page.contains(#"<meta http-equiv="Content-Security-Policy""#))
        #expect(PreviewPage.contentSecurityPolicy.hasPrefix("default-src 'none'"))
        for directive in ["script-src", "frame-src", "connect-src", "child-src"] {
            #expect(!PreviewPage.contentSecurityPolicy.contains(directive), "\(directive) must stay denied by default-src")
        }
    }

    @Test func followsTheSystemAppearance() {
        #expect(page.contains(#"<meta name="color-scheme" content="light dark">"#))
        #expect(page.contains("prefers-color-scheme: dark"))
    }
}
