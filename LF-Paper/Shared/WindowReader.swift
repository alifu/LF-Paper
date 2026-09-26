//
//  WindowReader.swift
//  LF-Paper
//

import AppKit
import SwiftUI

/// Reports the `NSWindow` hosting this view, for the few window features SwiftUI doesn't expose.
struct WindowReader: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowReportingView {
        WindowReportingView(onChange: onChange)
    }

    func updateNSView(_ view: WindowReportingView, context: Context) {
        view.onChange = onChange
    }
}

final class WindowReportingView: NSView {
    var onChange: (NSWindow?) -> Void

    init(onChange: @escaping (NSWindow?) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Deferred so SwiftUI state isn't changed in the middle of a view update.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            onChange(window)
        }
    }
}
