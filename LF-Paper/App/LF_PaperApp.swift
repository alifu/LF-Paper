//
//  LF_PaperApp.swift
//  LF-Paper
//
//  Created by Alif Ramadhoni on 26/09/26.
//

import SwiftUI

@main
struct LF_PaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Shared by every workspace window (to send files to it) and the Compare window.
    @State private var compare = CompareModel()

    var body: some Scene {
        WindowGroup {
            WorkspaceView()
                .environment(compare)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            SidebarCommands()
            TextEditingCommands()
            WorkspaceCommands()
        }

        Window("Compare JSON", id: CompareView.windowID) {
            CompareView(model: compare)
        }
        .defaultSize(width: 1000, height: 650)
    }
}
