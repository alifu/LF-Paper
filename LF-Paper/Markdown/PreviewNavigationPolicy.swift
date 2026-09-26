//
//  PreviewNavigationPolicy.swift
//  LF-Paper
//

import Foundation

/// Decides what happens when the preview wants to navigate somewhere.
/// The preview never leaves its page: web and mail links open outside the app, anything else is refused.
nonisolated enum PreviewNavigationPolicy {
    enum Decision: Equatable, Sendable {
        case allow
        case openExternally(URL)
        case deny
    }

    private static let externalSchemes: Set<String> = ["http", "https", "mailto"]

    static func decide(url: URL?, isLinkClick: Bool, pageURL: URL?) -> Decision {
        guard let url else { return .deny }
        // Not a click: only the page's own load is allowed (no meta refresh, forms or redirects).
        guard isLinkClick else {
            return isSameDocument(url, pageURL) ? .allow : .deny
        }
        if let scheme = url.scheme?.lowercased(), externalSchemes.contains(scheme) {
            return .openExternally(url)
        }
        if url.fragment != nil, isSameDocument(url, pageURL) {
            return .allow
        }
        return .deny
    }

    private static func isSameDocument(_ url: URL, _ pageURL: URL?) -> Bool {
        guard let pageURL else { return false }
        return url.scheme == pageURL.scheme
            && url.host() == pageURL.host()
            && url.path(percentEncoded: false) == pageURL.path(percentEncoded: false)
    }
}
