//
//  LF_PaperApp.swift
//  LF-Paper
//
//  Created by Alif Ramadhoni on 26/09/26.
//

import AppKit
import SwiftUI

@main
struct LF_PaperApp: App {
    static let workspaceWindowID = "workspace"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Shared by every workspace window (to send files to it) and the Compare window.
    @State private var compare = CompareModel()

    var body: some Scene {
        WindowGroup(id: Self.workspaceWindowID) {
            WorkspaceView()
                .environment(compare)
                .followsAppearanceSetting()
        }
        .defaultSize(width: 1100, height: 700)
        // Always open an editor window at launch, even when another window (like Compare) is restored.
        .defaultLaunchBehavior(.presented)
        .commands {
            SidebarCommands()
            TextEditingCommands()
            WorkspaceCommands()
        }

        Window("Compare JSON", id: CompareView.windowID) {
            CompareView(model: compare)
                .followsAppearanceSetting()
        }
        .defaultSize(width: 1000, height: 650)
        // A helper window: opened from the JSON menu or the sidebar, never on its own at launch.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .followsAppearanceSetting()
        }
    }
}

private struct FollowsAppearanceSetting: ViewModifier {
    @AppStorage(AppSettings.Key.appearance) private var appearance = AppAppearance.system

    func body(content: Content) -> some View {
        content.onChange(of: appearance, initial: true) { _, appearance in
            // App-wide, so every window (and the web preview inside it) switches together.
            NSApp.appearance = appearance.appearanceName.flatMap(NSAppearance.init(named:))
        }
    }
}

extension View {
    /// Applies Settings › Appearance to the whole app.
    func followsAppearanceSetting() -> some View {
        modifier(FollowsAppearanceSetting())
    }
}
