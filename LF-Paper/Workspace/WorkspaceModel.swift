//
//  WorkspaceModel.swift
//  LF-Paper
//

import Foundation
import Observation
import os

/// State for one workspace window: the open folder, its lazily loaded tree,
/// the selection and the open document.
@Observable
final class WorkspaceModel {
    private enum NewItem {
        case file
        case folder

        var baseName: String { self == .file ? "Untitled" : "New Folder" }
        var fileExtension: String? { self == .file ? "md" : nil }
    }

    private static let logger = Logger(subsystem: "AppWork.LF-Paper", category: "Workspace")

    private(set) var rootURL: URL?
    /// Loaded folder contents. Only the root and expanded folders are kept up to date.
    private(set) var childrenByFolder: [URL: [FileItem]] = [:]
    private(set) var expandedFolders: Set<URL> = []
    private(set) var document: OpenDocument?
    var selection: URL? {
        didSet {
            if selection != oldValue { openSelectedFile() }
        }
    }
    var showsHiddenFiles = false {
        didSet {
            if showsHiddenFiles != oldValue { reloadAll() }
        }
    }
    var isFolderPickerPresented = false
    var presentedError: AppError?

    @ObservationIgnored private let fileService: any FileService
    @ObservationIgnored private let bookmarkStore: BookmarkStore
    @ObservationIgnored private let watchesFileSystem: Bool
    @ObservationIgnored private var rootAccess: SecurityScopedAccess?
    @ObservationIgnored private var watcher: FileWatcher?

    init(
        fileService: any FileService = LocalFileService(),
        bookmarkStore: BookmarkStore = BookmarkStore(),
        watchesFileSystem: Bool = true
    ) {
        self.fileService = fileService
        self.bookmarkStore = bookmarkStore
        self.watchesFileSystem = watchesFileSystem
    }

    // MARK: Opening

    func openFolder(_ url: URL) {
        let access = SecurityScopedAccess(url: url)
        let items: [FileItem]
        do throws(AppError) {
            items = try fileService.contents(of: url, includeHidden: showsHiddenFiles)
        } catch {
            present(error)
            return
        }
        rootAccess = access
        rootURL = url
        childrenByFolder = [url: items]
        expandedFolders = []
        selection = nil
        document = nil
        remember(url)
        startWatching(url)
    }

    func handleFolderPickerResult(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            openFolder(url)
        case .failure(let error):
            Self.logger.error("Folder picker failed: \(error.localizedDescription)")
        }
    }

    /// Reopens the folder from the last launch, if it still exists.
    func restoreLastFolder() {
        guard rootURL == nil, let url = bookmarkStore.restore() else { return }
        openFolder(url)
        if rootURL == nil {
            bookmarkStore.clear()
        }
    }

    // MARK: Tree

    func children(of folder: URL) -> [FileItem] {
        childrenByFolder[folder] ?? []
    }

    /// The loaded item at `url`, matched by path so spelling differences
    /// (like a trailing slash) don't matter.
    func item(at url: URL) -> FileItem? {
        childrenByFolder.values.lazy.flatMap { $0 }.first { Self.isSamePath($0.url, url) }
    }

    func setExpanded(_ folder: URL, _ isExpanded: Bool) {
        guard isExpanded else {
            expandedFolders.remove(folder)
            return
        }
        guard childrenByFolder[folder] != nil || load(folder) else { return }
        expandedFolders.insert(folder)
    }

    /// Re-reads the root and every expanded folder, dropping anything that disappeared.
    func reloadAll() {
        guard let rootURL else { return }
        let folders = [rootURL] + expandedFolders.filter { $0 != rootURL }
        var reloaded: [URL: [FileItem]] = [:]
        for folder in folders {
            do throws(AppError) {
                reloaded[folder] = try fileService.contents(of: folder, includeHidden: showsHiddenFiles)
            } catch .fileNotFound {
                continue // Deleted or renamed outside the app.
            } catch {
                present(error)
            }
        }
        childrenByFolder = reloaded
        expandedFolders = expandedFolders.filter { reloaded[$0] != nil }
        dropMissingSelectionAndDocument()
    }

    /// Where "New File"/"New Folder" go: the folder itself, or the folder containing the file.
    func targetFolder(for item: FileItem?) -> URL? {
        guard let item else { return rootURL }
        if item.isFolder { return item.url }
        return childrenByFolder.first { $0.value.contains(item) }?.key ?? item.url.deletingLastPathComponent()
    }

    // MARK: File operations

    func createFile(in folder: URL) {
        create(.file, in: folder)
    }

    func createFolder(in folder: URL) {
        create(.folder, in: folder)
    }

    func rename(_ item: FileItem, to newName: String) {
        do throws(AppError) {
            let renamed = try fileService.rename(item.url, to: newName)
            if let document, Self.isSamePath(document.url, item.url) {
                self.document = document.moving(to: renamed)
            }
            let wasSelected = selection.map { Self.isSamePath($0, item.url) } ?? false
            reloadAll()
            if wasSelected {
                selection = self.item(at: renamed)?.url ?? renamed
            }
        } catch {
            present(error)
        }
    }

    func moveToTrash(_ item: FileItem) {
        do throws(AppError) {
            try fileService.moveToTrash(item.url)
            reloadAll()
        } catch {
            present(error)
        }
    }

    // MARK: Document

    func updateDocumentText(_ text: String) {
        document = document?.editing(text)
    }

    func save() {
        guard let document, document.isDirty else { return }
        do throws(AppError) {
            try fileService.write(document.text, to: document.url)
            self.document = document.markingSaved()
        } catch {
            present(error)
        }
    }

    // MARK: Private

    private func create(_ newItem: NewItem, in folder: URL) {
        guard childrenByFolder[folder] != nil || load(folder) else { return }
        let existingNames = Set(children(of: folder).map(\.name))
        let name = FileNaming.uniqueName(
            base: newItem.baseName,
            fileExtension: newItem.fileExtension,
            existing: existingNames
        )
        do throws(AppError) {
            let created = switch newItem {
            case .file: try fileService.createFile(named: name, in: folder)
            case .folder: try fileService.createFolder(named: name, in: folder)
            }
            if folder != rootURL {
                expandedFolders.insert(folder)
            }
            reloadAll()
            selection = item(at: created)?.url ?? created
        } catch {
            present(error)
        }
    }

    @discardableResult
    private func load(_ folder: URL) -> Bool {
        do throws(AppError) {
            childrenByFolder[folder] = try fileService.contents(of: folder, includeHidden: showsHiddenFiles)
            return true
        } catch {
            present(error)
            return false
        }
    }

    private func openSelectedFile() {
        guard let selection,
              let item = item(at: selection),
              !item.isFolder,
              !(document.map { Self.isSamePath($0.url, selection) } ?? false)
        else { return }
        do throws(AppError) {
            document = OpenDocument(url: item.url, text: try fileService.read(item.url))
        } catch {
            present(error)
        }
    }

    private func dropMissingSelectionAndDocument() {
        if let selection, !fileService.exists(selection) {
            self.selection = nil
        }
        // TODO(Phase 2): ask before discarding unsaved changes to a file deleted on disk.
        if let document, !fileService.exists(document.url) {
            self.document = nil
        }
    }

    private func remember(_ folder: URL) {
        do throws(AppError) {
            try bookmarkStore.save(folder)
        } catch {
            Self.logger.error("Could not remember folder for next launch: \(String(describing: error))")
        }
    }

    private func startWatching(_ folder: URL) {
        guard watchesFileSystem else { return }
        watcher = FileWatcher(url: folder) { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.reloadAll() }
        }
        if watcher == nil {
            Self.logger.error("Could not watch the folder for outside changes")
        }
    }

    private func present(_ error: AppError) {
        Self.logger.error("Workspace operation failed: \(String(describing: error))")
        presentedError = error
    }

    private static func isSamePath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.pathComponents == rhs.standardizedFileURL.pathComponents
    }
}
