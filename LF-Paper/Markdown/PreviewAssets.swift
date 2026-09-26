//
//  PreviewAssets.swift
//  LF-Paper
//

import Foundation
import UniformTypeIdentifiers

/// How the preview loads local files (images) through its own URL scheme.
///
/// The page's base URL is `lfpaper-asset://local/<document folder>/`, so relative image paths
/// resolve naturally. Requests are only served for files inside the open workspace folder.
nonisolated enum PreviewAssets {
    static let scheme = "lfpaper-asset"
    private static let host = "local"

    static func baseURL(for folder: URL) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        let path = folder.standardizedFileURL.path(percentEncoded: false)
        components.path = path.hasSuffix("/") ? path : path + "/"
        return components.url ?? folder
    }

    /// The file an asset request refers to, or `nil` if it isn't strictly inside `root`
    /// (after resolving `..` and symlinks).
    static func fileURL(for assetURL: URL, within root: URL) -> URL? {
        guard assetURL.scheme == scheme, assetURL.host() == host else { return nil }
        let requested = URL(filePath: assetURL.path(percentEncoded: false))
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let requestedComponents = requested.pathComponents
        guard requestedComponents.count > rootComponents.count,
              requestedComponents.starts(with: rootComponents)
        else { return nil }
        return requested
    }

    static func mimeType(for file: URL) -> String {
        UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}
