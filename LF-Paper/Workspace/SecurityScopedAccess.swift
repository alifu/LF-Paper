//
//  SecurityScopedAccess.swift
//  LF-Paper
//

import Foundation

/// Keeps a security-scoped URL accessible for as long as this object lives.
/// URLs that aren't security-scoped are fine: access simply isn't needed for them.
nonisolated final class SecurityScopedAccess: Sendable {
    let url: URL
    private let isAccessing: Bool

    init(url: URL) {
        self.url = url
        isAccessing = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if isAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
