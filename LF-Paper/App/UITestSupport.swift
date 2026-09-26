//
//  UITestSupport.swift
//  LF-Paper
//

#if DEBUG
import Foundation

/// Debug-only hooks for the UI tests: launched with `-UITestFixture YES`, the app opens a fresh
/// folder of sample files inside its own sandbox and keeps its settings apart from the real ones.
/// (Launch arguments of the form `-Key value` become settings, so the flag needs its value.)
enum UITestSupport {
    static let launchSetting = "UITestFixture"
    private static let defaultsSuite = "AppWork.LF-Paper.UITests"

    static let fixtureFiles: [(name: String, contents: String)] = [
        ("README.md", "# Fixture\n\nHello from the UI tests.\n"),
        ("data.json", #"{"name":"Ada","languages":["math","poetry"],"active":true}"# + "\n"),
        ("other.json", #"{"name":"Grace","languages":["math","navy"],"active":true}"# + "\n"),
    ]

    static var isActive: Bool {
        UserDefaults.standard.bool(forKey: launchSetting)
    }

    /// A workspace that doesn't remember folders in the real settings.
    static func makeModel() -> WorkspaceModel {
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuite)
        let defaults = UserDefaults(suiteName: defaultsSuite) ?? .standard
        return WorkspaceModel(
            bookmarkStore: BookmarkStore(defaults: defaults),
            recentFolders: RecentFolders(defaults: defaults),
            watchesFileSystem: false
        )
    }

    /// Writes the sample files to a new folder in the app's temporary directory.
    static func makeFixtureFolder() -> URL? {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "UITestFixture-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in fixtureFiles {
                try Data(file.contents.utf8).write(to: folder.appending(path: file.name))
            }
            return folder
        } catch {
            return nil
        }
    }
}
#endif
