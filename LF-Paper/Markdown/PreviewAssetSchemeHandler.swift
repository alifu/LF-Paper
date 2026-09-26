//
//  PreviewAssetSchemeHandler.swift
//  LF-Paper
//

import Foundation
import WebKit

/// Serves `lfpaper-asset://` requests from the workspace folder; everything else fails.
/// Runs in the app process, which holds the folder's security-scoped access.
final class PreviewAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    var root: URL?

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              let root,
              let file = PreviewAssets.fileURL(for: requestURL, within: root)
        else {
            urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }
        do {
            let data = try Data(contentsOf: file)
            let response = URLResponse(
                url: requestURL,
                mimeType: PreviewAssets.mimeType(for: file),
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // Responses are delivered synchronously in `start`, so there is nothing to cancel.
    }
}
