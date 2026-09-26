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

    var body: some Scene {
        WindowGroup {
            WorkspaceView()
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            SidebarCommands()
            TextEditingCommands()
            WorkspaceCommands()
        }
    }
}
