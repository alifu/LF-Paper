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
    /// Something that would replace the open document and so waits for a decision about unsaved changes.
    enum PendingAction: Equatable {
        case openFile(URL)
        case openFolder(URL)
    }

    enum UnsavedChangesDecision {
        case save
        case discard
        case cancel
    }

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
    /// The open file was deleted on disk while it had unsaved changes. Saving recreates it.
    private(set) var isDocumentMissingOnDisk = false
    private(set) var pendingAction: PendingAction?
    var selection: URL? {
        didSet {
            if selection != oldValue { selectionDidChange() }
        }
    }
    var showsHiddenFiles = false {
        didSet {
            if showsHiddenFiles != oldValue { reloadAll() }
        }
    }
    var isFolderPickerPresented = false
    var editorLayout: EditorLayout = .split
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

    var hasUnsavedChanges: Bool {
        document?.isDirty == true || isDocumentMissingOnDisk
    }

    // MARK: Opening

    func openFolder(_ url: URL) {
        guard !hasUnsavedChanges else {
            pendingAction = .openFolder(url)
            return
        }
        performOpenFolder(url)
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
        performOpenFolder(url)
        if rootURL == nil {
            bookmarkStore.clear()
        }
    }

    // MARK: Unsaved changes

    func resolvePendingAction(_ decision: UnsavedChangesDecision) {
        guard let action = pendingAction else { return }
        pendingAction = nil
        switch decision {
        case .save:
            if save() { perform(action) } else { cancel(action) }
        case .discard:
            discardUnsavedChanges()
            perform(action)
        case .cancel:
            cancel(action)
        }
    }

    func discardUnsavedChanges() {
        if isDocumentMissingOnDisk {
            document = nil
            isDocumentMissingOnDisk = false
        } else {
            document = document?.reverted()
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

    /// Re-reads the root and every expanded folder, dropping anything that disappeared,
    /// and brings the open document in line with the disk.
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
        if let selection, !fileService.exists(selection) {
            self.selection = nil
        }
        syncDocumentWithDisk()
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

    /// Writes unsaved changes. Returns `false` (and presents the error) if the write failed.
    @discardableResult
    func save() -> Bool {
        guard let document, hasUnsavedChanges else { return true }
        do throws(AppError) {
            try fileService.write(document.text, to: document.url)
            self.document = document.markingSaved()
            isDocumentMissingOnDisk = false
            return true
        } catch {
            present(error)
            return false
        }
    }

    // MARK: Private

    private func performOpenFolder(_ url: URL) {
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
        document = nil
        isDocumentMissingOnDisk = false
        selection = nil
        remember(url)
        startWatching(url)
    }

    private func perform(_ action: PendingAction) {
        switch action {
        case .openFile(let url): openFile(at: url)
        case .openFolder(let url): performOpenFolder(url)
        }
    }

    private func cancel(_ action: PendingAction) {
        guard case .openFile = action else { return }
        // Put the highlight back on the file that's still open.
        selection = document.map { item(at: $0.url)?.url ?? $0.url }
    }

    private func selectionDidChange() {
        guard let selection,
              let item = item(at: selection),
              !item.isFolder,
              !isOpen(item.url)
        else { return }
        guard !hasUnsavedChanges else {
            pendingAction = .openFile(item.url)
            return
        }
        openFile(at: item.url)
    }

    private func openFile(at url: URL) {
        do throws(AppError) {
            document = OpenDocument(url: url, text: try fileService.read(url))
            isDocumentMissingOnDisk = false
        } catch {
            present(error)
        }
    }

    private func isOpen(_ url: URL) -> Bool {
        document.map { Self.isSamePath($0.url, url) } ?? false
    }

    /// Unedited documents follow the disk; edited ones are never overwritten or dropped.
    private func syncDocumentWithDisk() {
        guard let document else { return }
        guard fileService.exists(document.url) else {
            if document.isDirty {
                isDocumentMissingOnDisk = true
            } else {
                self.document = nil
            }
            return
        }
        isDocumentMissingOnDisk = false
        guard !document.isDirty else { return }
        do throws(AppError) {
            let diskText = try fileService.read(document.url)
            if diskText != document.text {
                self.document = OpenDocument(url: document.url, text: diskText)
            }
        } catch {
            present(error)
        }
    }

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
