//
//  WorkspaceModel.swift
//  LF-Paper
//

import Foundation
import Observation
import os

/// State for one workspace window: the open folder, its lazily loaded tree,
/// the selection and the open files (tabs).
@Observable
final class WorkspaceModel {
    /// Something that would throw away unsaved changes and so waits for a decision first.
    enum PendingAction: Equatable {
        case closeTab(UUID)
        case openFolder(URL)
    }

    enum UnsavedChangesDecision {
        case save
        case discard
        case cancel
    }

    private enum NewItem {
        case file(NewFileType)
        case folder

        var baseName: String {
            switch self {
            case .file: "Untitled"
            case .folder: "New Folder"
            }
        }

        var fileExtension: String? {
            switch self {
            case .file(let type): type.fileExtension
            case .folder: nil
            }
        }
    }

    private static let logger = Logger(subsystem: "AppWork.LF-Paper", category: "Workspace")

    private(set) var rootURL: URL?
    /// Loaded folder contents. Only the root and expanded folders are kept up to date.
    private(set) var childrenByFolder: [URL: [FileItem]] = [:]
    private(set) var expandedFolders: Set<URL> = []
    private var openTabs: DocumentTabs = .empty {
        didSet { json.documentDidChange(document) }
    }
    /// Validation and tree for the open document when it's JSON.
    let json = JSONSession()
    /// The latest request for the editor to select and show a range (a JSON error or tree value).
    private(set) var revealRequest: RevealRequest?
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
    /// How long to wait after typing stops before saving automatically; `nil` turns autosave off.
    var autosaveDelay: Duration?
    /// The pending autosave; tests await it.
    @ObservationIgnored private(set) var autosaveTask: Task<Void, Never>?

    @ObservationIgnored private let fileService: any FileService
    @ObservationIgnored private let bookmarkStore: BookmarkStore
    @ObservationIgnored private let recentFolders: RecentFolders
    @ObservationIgnored private let watchesFileSystem: Bool
    @ObservationIgnored private var rootAccess: SecurityScopedAccess?
    @ObservationIgnored private var watcher: FileWatcher?

    init(
        fileService: any FileService = LocalFileService(),
        bookmarkStore: BookmarkStore = BookmarkStore(),
        recentFolders: RecentFolders = .shared,
        watchesFileSystem: Bool = true
    ) {
        self.fileService = fileService
        self.bookmarkStore = bookmarkStore
        self.recentFolders = recentFolders
        self.watchesFileSystem = watchesFileSystem
    }

    /// The open files, in tab order.
    var tabs: [OpenDocument] { openTabs.documents }

    /// The file in the active tab.
    var document: OpenDocument? { openTabs.active }

    /// Whether any tab has unsaved changes.
    var hasUnsavedChanges: Bool { openTabs.hasUnsavedChanges }

    var activeTabHasUnsavedChanges: Bool {
        document.map { openTabs.hasUnsavedChanges($0.id) } ?? false
    }

    /// The active file was deleted on disk while it had unsaved changes. Saving recreates it.
    var isDocumentMissingOnDisk: Bool {
        document.map { openTabs.missingOnDisk.contains($0.id) } ?? false
    }

    func hasUnsavedChanges(inTab id: UUID) -> Bool {
        openTabs.hasUnsavedChanges(id)
    }

    /// Open files with unsaved changes, in tab order.
    var unsavedDocuments: [OpenDocument] {
        tabs.filter { openTabs.hasUnsavedChanges($0.id) }
    }

    /// The files the pending prompt is about.
    var pendingActionDocuments: [OpenDocument] {
        switch pendingAction {
        case .closeTab(let id): openTabs.document(withID: id).map { [$0] } ?? []
        case .openFolder: unsavedDocuments
        case nil: []
        }
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
        switch (decision, action) {
        case (.save, .closeTab(let id)):
            if save(id) { removeTab(id) }
        case (.save, .openFolder(let url)):
            if saveAll() { performOpenFolder(url) }
        case (.discard, .closeTab(let id)):
            removeTab(id)
        case (.discard, .openFolder(let url)):
            discardUnsavedChanges()
            performOpenFolder(url)
        case (.cancel, _):
            break
        }
    }

    /// Reverts every tab to its saved text; tabs whose file is gone are closed.
    func discardUnsavedChanges() {
        for id in openTabs.missingOnDisk {
            openTabs = openTabs.closing(id)
        }
        for document in tabs where document.isDirty {
            openTabs = openTabs.replacing(document.reverted())
        }
    }

    // MARK: Tabs

    func activateTab(_ id: UUID) {
        openTabs = openTabs.activating(id)
        syncSelectionWithActiveTab()
    }

    func activateNextTab() {
        openTabs.neighbour(offset: 1).map(activateTab)
    }

    func activatePreviousTab() {
        openTabs.neighbour(offset: -1).map(activateTab)
    }

    /// Closes a tab, first asking about unsaved changes.
    func closeTab(_ id: UUID) {
        guard !openTabs.hasUnsavedChanges(id) else {
            pendingAction = .closeTab(id)
            return
        }
        removeTab(id)
    }

    func closeActiveTab() {
        document.map { closeTab($0.id) }
    }

    // MARK: Tree

    func children(of folder: URL) -> [FileItem] {
        childrenByFolder[folder] ?? []
    }

    /// The loaded item at `url`, matched by path so spelling differences
    /// (like a trailing slash) don't matter.
    func item(at url: URL) -> FileItem? {
        childrenByFolder.values.lazy.flatMap { $0 }.first { $0.url.refersToSameFile(as: url) }
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
        syncDocumentsWithDisk()
    }

    /// Where "New File"/"New Folder" go: the folder itself, or the folder containing the file.
    func targetFolder(for item: FileItem?) -> URL? {
        guard let item else { return rootURL }
        if item.isFolder { return item.url }
        return childrenByFolder.first { $0.value.contains(item) }?.key ?? item.url.deletingLastPathComponent()
    }

    /// Where File › New puts items: next to the selected file, inside the selected folder, or at the root.
    var newItemFolder: URL? {
        targetFolder(for: selection.flatMap(item(at:)))
    }

    // MARK: File operations

    func createFile(in folder: URL, type: NewFileType = .markdown) {
        create(.file(type), in: folder)
    }

    func createFolder(in folder: URL) {
        create(.folder, in: folder)
    }

    func rename(_ item: FileItem, to newName: String) {
        do throws(AppError) {
            let renamed = try fileService.rename(item.url, to: newName)
            if let renamedDocument = openTabs.document(at: item.url) {
                openTabs = openTabs.replacing(renamedDocument.moving(to: renamed))
            }
            let wasSelected = selection?.refersToSameFile(as: item.url) ?? false
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

    var isJSONDocument: Bool {
        document.map { FileKind(fileExtension: $0.url.pathExtension) == .json } ?? false
    }

    func updateDocumentText(_ text: String) {
        guard let document else { return }
        openTabs = openTabs.replacing(document.editing(text))
        scheduleAutosave()
    }

    /// A file's text, including unsaved edits when it's open in a tab. Presents read errors.
    func text(of item: FileItem) -> String? {
        if let document = openTabs.document(at: item.url) {
            return document.text
        }
        do throws(AppError) {
            return try fileService.read(item.url)
        } catch {
            present(error)
            return nil
        }
    }

    /// Asks the editor to select `range` and scroll to it. Each call is a new request.
    func reveal(_ range: NSRange, focusesEditor: Bool) {
        revealRequest = RevealRequest(range: range, focusesEditor: focusesEditor)
    }

    /// Writes the active tab's unsaved changes. Returns `false` (and presents the error) if the write failed.
    @discardableResult
    func save() -> Bool {
        document.map { save($0.id) } ?? true
    }

    /// Writes every tab with unsaved changes, stopping at the first failure.
    @discardableResult
    func saveAll() -> Bool {
        unsavedDocuments.allSatisfy { save($0.id) }
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
        openTabs = .empty
        selection = nil
        remember(url)
        startWatching(url)
    }

    private func save(_ id: UUID) -> Bool {
        guard let document = openTabs.document(withID: id), openTabs.hasUnsavedChanges(id) else { return true }
        do throws(AppError) {
            try fileService.write(document.text, to: document.url)
            openTabs = openTabs.replacing(document.markingSaved()).marking(id, missingOnDisk: false)
            return true
        } catch {
            present(error)
            return false
        }
    }

    private func removeTab(_ id: UUID) {
        openTabs = openTabs.closing(id)
        syncSelectionWithActiveTab()
    }

    /// Highlights the active tab's file in the sidebar (or nothing when no tab is open).
    private func syncSelectionWithActiveTab() {
        let url = document.map { item(at: $0.url)?.url ?? $0.url }
        if selection != url { selection = url }
    }

    /// Opening a file shows its tab, adding one if it isn't open yet.
    private func selectionDidChange() {
        guard let selection,
              let item = item(at: selection),
              !item.isFolder
        else { return }
        if let open = openTabs.document(at: item.url) {
            openTabs = openTabs.activating(open.id)
        } else {
            openFile(at: item.url)
        }
    }

    private func openFile(at url: URL) {
        do throws(AppError) {
            openTabs = openTabs.opening(OpenDocument(url: url, text: try fileService.read(url)))
        } catch {
            present(error)
        }
    }

    /// Saves every edited tab once typing has paused for `autosaveDelay`.
    /// Files deleted on disk are left for the user to recreate deliberately.
    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard let autosaveDelay else {
            autosaveTask = nil
            return
        }
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: autosaveDelay) // a cancelled sleep ends early; checked below
            guard !Task.isCancelled, let self else { return }
            for document in self.tabs where document.isDirty && !self.openTabs.missingOnDisk.contains(document.id) {
                _ = self.save(document.id)
            }
        }
    }

    /// Unedited tabs follow the disk; edited ones are never overwritten or dropped.
    private func syncDocumentsWithDisk() {
        let activeFileBefore = document?.url
        for document in tabs {
            syncWithDisk(document)
        }
        // Only move the sidebar highlight when the active tab closed; a folder the user
        // selected shouldn't jump away on every outside change.
        if document?.url != activeFileBefore {
            syncSelectionWithActiveTab()
        }
    }

    private func syncWithDisk(_ document: OpenDocument) {
        guard fileService.exists(document.url) else {
            openTabs = document.isDirty
                ? openTabs.marking(document.id, missingOnDisk: true)
                : openTabs.closing(document.id)
            return
        }
        openTabs = openTabs.marking(document.id, missingOnDisk: false)
        guard !document.isDirty else { return }
        do throws(AppError) {
            let diskText = try fileService.read(document.url)
            if diskText != document.text {
                openTabs = openTabs.reloading(document.id, with: OpenDocument(url: document.url, text: diskText))
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
            let created: URL
            switch newItem {
            case .file(let type):
                created = try fileService.createFile(named: name, in: folder)
                if !type.initialContents.isEmpty {
                    try fileService.write(type.initialContents, to: created)
                }
            case .folder:
                created = try fileService.createFolder(named: name, in: folder)
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
        recentFolders.add(folder)
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
}
