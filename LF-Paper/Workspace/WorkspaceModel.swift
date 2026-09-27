//
//  WorkspaceModel.swift
//  LF-Paper
//

import AppKit
import Observation
import os

/// State for one workspace window: the open folder, its lazily loaded tree,
/// the selection, the open files (tabs) and the scratchpad.
///
/// Split by concern: the folder tree and file operations (`+Files`), the tab session
/// (`+TabSession`), the scratchpad (`+Scratchpad`) and the open document (`+Document`).
/// The pure logic lives in value types (`FolderTree`, `DocumentTabs`, `TabSession`,
/// `TabSelectionMemory`); the model coordinates them.
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

    static let logger = Logger(subsystem: "AppWork.LF-Paper", category: "Workspace")
    /// How many recently opened files Quick Open remembers.
    private static let recentFilesLimit = 50

    // Internal rather than private only so the model's extensions in other files can update
    // them; views and tests use the API below (`tabs`, `document`, `children(of:)`, …).

    /// The open folder and its loaded subfolders.
    var folderTree: FolderTree = .empty
    var openTabs: DocumentTabs = .empty {
        didSet {
            json.documentDidChange(document)
            // Typing also changes the tabs; only the list and the active tab are remembered.
            if !isSwitchingFolders,
               oldValue.documents.map(\.url) != openTabs.documents.map(\.url) || oldValue.active?.url != openTabs.active?.url {
                saveTabSession()
            }
        }
    }
    /// The latest editor selection of each open tab, for the tab session.
    @ObservationIgnored var selectionMemory: TabSelectionMemory = .empty
    /// Whether each document has a very long line, remembered with the text length it was checked at.
    @ObservationIgnored var longLineChecks: [UUID: (length: Int, hasLongLine: Bool)] = [:]
    /// Documents whose "Format this file?" offer was turned down.
    var declinedFormatOffers: Set<UUID> = []
    @ObservationIgnored let fileService: any FileService
    @ObservationIgnored let tabSessions: TabSessionStore

    let scratchpad = ScratchpadState()
    /// Every Markdown and JSON file under the folder, for Quick Open and Search in Folder.
    private(set) var fileIndex: [IndexedFile] = []
    /// The indexing in progress; tests await it.
    @ObservationIgnored private(set) var indexTask: Task<Void, Never>?
    /// Files opened in this window, newest first.
    private(set) var recentFiles: [URL] = []
    var isQuickOpenPresented = false
    var sidebarMode: SidebarMode = .files
    /// Changes whenever Search in Folder should take keyboard focus.
    private(set) var searchFocusRequest: UUID?
    let search = FolderSearchSession()
    /// Replace All over the search results.
    let replace = ReplaceSession()
    /// The Generate Swift Model sheet, while it's open.
    var swiftModelGenerator: SwiftModelSession?
    /// Where the editor and the Markdown preview scroll to follow each other.
    let scrollSync = ScrollSync()
    /// The headings of the Markdown file, for the Outline sidebar.
    let outline = OutlineSession()
    /// The open JSON file checked against its schema.
    let schema = SchemaSession()
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

    @ObservationIgnored private let autosave = AutosaveScheduler()
    @ObservationIgnored private let bookmarkStore: BookmarkStore
    @ObservationIgnored private let recentFolders: RecentFolders
    @ObservationIgnored private let watchesFileSystem: Bool
    @ObservationIgnored private var rootAccess: SecurityScopedAccess?
    @ObservationIgnored private var watcher: FileWatcher?
    /// Set while one folder's tabs are swapped for another's, so neither session is overwritten.
    @ObservationIgnored private var isSwitchingFolders = false

    init(
        fileService: any FileService = LocalFileService(),
        bookmarkStore: BookmarkStore = BookmarkStore(),
        recentFolders: RecentFolders = .shared,
        tabSessions: TabSessionStore? = nil,
        watchesFileSystem: Bool = true
    ) {
        self.fileService = fileService
        self.bookmarkStore = bookmarkStore
        self.recentFolders = recentFolders
        // Next to the folder bookmarks by default, so tests with their own settings keep sessions there too.
        self.tabSessions = tabSessions ?? TabSessionStore(defaults: bookmarkStore.defaults)
        self.watchesFileSystem = watchesFileSystem
    }

    var rootURL: URL? { folderTree.root }

    /// The open files, in tab order.
    var tabs: [OpenDocument] { openTabs.documents }

    /// The file in the active tab; `nil` while the scratchpad is showing.
    var document: OpenDocument? { isScratchpadActive ? nil : openTabs.active }

    /// Everything the editor keeps an undo history for: the open files and the scratchpad.
    var editorDocumentIDs: Set<UUID> { Set(tabs.map(\.id)).union([scratchpadID]) }

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

    /// How long to wait after typing stops before saving automatically; `nil` turns autosave off.
    var autosaveDelay: Duration? {
        get { autosave.delay }
        set { autosave.delay = newValue }
    }

    /// The pending autosave; tests await it.
    var autosaveTask: Task<Void, Never>? { autosave.task }

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

    /// Reverts every tab to its saved text; tabs whose file is gone, or was never saved, are closed.
    func discardUnsavedChanges() {
        for id in openTabs.missingOnDisk.union(tabs.filter(\.isNew).map(\.id)) {
            openTabs = openTabs.closing(id)
        }
        for document in tabs where document.isDirty {
            openTabs = openTabs.replacing(document.reverted())
        }
    }

    // MARK: Tabs

    func activateTab(_ id: UUID) {
        setScratchpadActive(false)
        openTabs = openTabs.activating(id)
        document.map { noteOpened($0.url) }
        syncSelectionWithActiveTab()
        revealPendingSelection()
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

    /// Opens `text` in a new, unsaved tab next to `source`, named `baseName` (or like `source`)
    /// with another extension.
    func openNewFile(_ text: String, fileExtension: String, nextTo source: URL, baseName: String? = nil) {
        let folder = source.deletingLastPathComponent()
        let taken = Set(children(of: folder).map(\.name) + tabs.filter { $0.url.deletingLastPathComponent().refersToSameFile(as: folder) }.map(\.url.lastPathComponent))
        let base = baseName ?? source.deletingPathExtension().lastPathComponent
        let name = FileNaming.uniqueName(base: base, fileExtension: fileExtension, existing: taken)
        setScratchpadActive(false)
        openTabs = openTabs.opening(.newFile(at: folder.appending(path: name, directoryHint: .notDirectory), text: text))
        syncSelectionWithActiveTab() // so choosing the source file in the sidebar switches back to it
    }

    /// Edit › Find in Folder (⇧⌘F): shows the search in the sidebar and focuses its field.
    func showFolderSearch() {
        sidebarMode = .search
        searchFocusRequest = UUID()
    }

    /// Re-lists every supported file under the folder in the background.
    func refreshFileIndex() {
        indexTask?.cancel()
        guard let rootURL else {
            fileIndex = []
            return
        }
        let includeHidden = showsHiddenFiles
        indexTask = Task { [weak self] in
            let files = await Self.index(rootURL, includeHidden: includeHidden)
            guard let self, !Task.isCancelled, self.rootURL == rootURL else { return }
            self.fileIndex = files
        }
    }

    @concurrent
    private static func index(_ root: URL, includeHidden: Bool) async -> [IndexedFile] {
        FileIndexer.index(root: root, includeHidden: includeHidden)
    }

    // MARK: Editing and saving

    func updateDocumentText(_ text: String) {
        guard let document else { return }
        updateText(ofTab: document.id, to: text)
    }

    /// Edits any tab's text, as typing in it would (Replace All edits tabs that aren't showing).
    func updateText(ofTab id: UUID, to text: String) {
        guard let document = openTabs.document(withID: id) else { return }
        openTabs = openTabs.replacing(document.editing(text))
        autosave.schedule { [weak self] in self?.autosaveEditedTabs() }
    }

    /// Asks the editor to select `range` and scroll to it. Each call is a new request.
    func reveal(_ range: NSRange, focusesEditor: Bool, highlights: Bool = true) {
        revealRequest = RevealRequest(range: range, focusesEditor: focusesEditor, highlights: highlights)
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

    private func save(_ id: UUID) -> Bool {
        guard let document = openTabs.document(withID: id), openTabs.hasUnsavedChanges(id) else { return true }
        do throws(AppError) {
            try fileService.write(document.text, to: document.url)
            openTabs = openTabs.replacing(document.markingSaved()).marking(id, missingOnDisk: false)
            if document.isNew { reloadAll() } // show the new file in the sidebar
            return true
        } catch {
            present(error)
            return false
        }
    }

    // MARK: Shared with the extensions

    /// Highlights the active tab's file in the sidebar (or nothing when no tab is open).
    func syncSelectionWithActiveTab() {
        let url = document.map { item(at: $0.url)?.url ?? $0.url }
        if selection != url { selection = url }
    }

    /// Shows or hides the scratchpad, telling the JSON session the visible document changed.
    func setScratchpadActive(_ isActive: Bool) {
        guard scratchpad.isActive != isActive else { return }
        scratchpad.isActive = isActive
        json.documentDidChange(document)
    }

    func present(_ error: AppError) {
        Self.logger.error("Workspace operation failed: \(String(describing: error))")
        presentedError = error
    }

    // MARK: Private

    private func performOpenFolder(_ url: URL) {
        saveTabSession() // the folder being left, with its latest selections
        let access = SecurityScopedAccess(url: url)
        let items: [FileItem]
        do throws(AppError) {
            items = try fileService.contents(of: url, includeHidden: showsHiddenFiles)
        } catch {
            present(error)
            return
        }
        rootAccess = access
        isSwitchingFolders = true
        folderTree = .opening(url, items: items)
        openTabs = .empty
        selectionMemory = .empty
        selection = nil
        restoreTabSession(for: url)
        isSwitchingFolders = false
        fileIndex = []
        recentFiles = []
        search.reset()
        replace.reset()
        refreshFileIndex()
        remember(url)
        startWatching(url)
    }

    /// Saves every edited tab autosave may write, once typing has paused.
    private func autosaveEditedTabs() {
        for id in AutosaveScheduler.documentsToSave(in: openTabs) {
            _ = save(id)
        }
    }

    private func removeTab(_ id: UUID) {
        openTabs = openTabs.closing(id)
        syncSelectionWithActiveTab()
    }

    /// Opening a file shows its tab, adding one if it isn't open yet.
    private func selectionDidChange() {
        guard let selection,
              let item = item(at: selection),
              !item.isFolder
        else { return }
        setScratchpadActive(false)
        if let open = openTabs.document(at: item.url) {
            openTabs = openTabs.activating(open.id)
        } else {
            openFile(at: item.url)
        }
        document.map { noteOpened($0.url) }
        revealPendingSelection()
    }

    private func noteOpened(_ url: URL) {
        let others = recentFiles.filter { !$0.refersToSameFile(as: url) }
        recentFiles = Array(([url] + others).prefix(Self.recentFilesLimit))
    }

    private func openFile(at url: URL) {
        do throws(AppError) {
            openTabs = openTabs.opening(OpenDocument(url: url, text: try fileService.read(url)))
        } catch {
            present(error)
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
}
