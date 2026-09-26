//
//  PreviewPage.swift
//  LF-Paper
//

import Foundation

/// The HTML document the Markdown preview shows. Rendered Markdown goes inside `#content`.
nonisolated enum PreviewPage {
    /// Nothing may load except images (from the workspace or the web) and the inline stylesheet.
    static let contentSecurityPolicy =
        "default-src 'none'; img-src \(PreviewAssets.scheme): https: data:; style-src 'unsafe-inline'"

    static func html(body: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <meta name="color-scheme" content="light dark">
        <style>\(stylesheet)</style>
        </head>
        <body><article id="content" class="markdown-body">\(body)</article></body>
        </html>
        """
    }

    /// GitHub-like typography; colors follow the system appearance.
    private static let stylesheet = """
        :root {
          --fg: #1f2328; --muted: #59636e; --border: #d1d9e0; --link: #0969da;
          --code-bg: rgba(129, 139, 152, 0.12); --bg: #ffffff;
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --fg: #f0f6fc; --muted: #9198a1; --border: #3d444d; --link: #4493f8;
            --code-bg: rgba(101, 108, 118, 0.2); --bg: #1e1e1e;
          }
        }
        html, body { background: var(--bg); color: var(--fg); }
        body {
          margin: 0; padding: 24px 32px;
          font: 15px/1.6 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
          overflow-wrap: break-word;
        }
        .markdown-body > *:first-child { margin-top: 0; }
        h1, h2, h3, h4, h5, h6 { margin: 1.5em 0 0.5em; font-weight: 600; line-height: 1.25; }
        h1 { font-size: 2em; padding-bottom: 0.3em; border-bottom: 1px solid var(--border); }
        h2 { font-size: 1.5em; padding-bottom: 0.3em; border-bottom: 1px solid var(--border); }
        h3 { font-size: 1.25em; }
        p, ul, ol, blockquote, table, pre { margin: 0 0 1em; }
        a { color: var(--link); text-decoration: none; }
        a:hover { text-decoration: underline; }
        code, pre { font: 0.9em ui-monospace, "SF Mono", Menlo, monospace; }
        code { background: var(--code-bg); padding: 0.2em 0.4em; border-radius: 6px; }
        pre { background: var(--code-bg); padding: 16px; border-radius: 6px; overflow: auto; line-height: 1.45; }
        pre code { background: none; padding: 0; }
        blockquote { color: var(--muted); border-left: 0.25em solid var(--border); padding: 0 1em; margin-left: 0; }
        table { border-collapse: collapse; display: block; overflow: auto; }
        th, td { border: 1px solid var(--border); padding: 6px 13px; }
        th { font-weight: 600; }
        img { max-width: 100%; }
        hr { border: 0; border-top: 1px solid var(--border); margin: 1.5em 0; }
        li > input[type="checkbox"] { margin-right: 0.4em; }
        """
}
