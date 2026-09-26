//
//  WorkspaceModel.swift
//  LF-Paper
//

import AppKit
import Observation
import os

/// State for one workspace window: the open folder, its lazily loaded tree,
/// the selection, the open files (tabs) and the scratchpad.
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
    /// How many recently opened files Quick Open remembers.
    private static let recentFilesLimit = 50

    private(set) var rootURL: URL?
    /// Loaded folder contents. Only the root and expanded folders are kept up to date.
    private(set) var childrenByFolder: [URL: [FileItem]] = [:]
    private(set) var expandedFolders: Set<URL> = []
    private var openTabs: DocumentTabs = .empty {
        didSet {
            json.documentDidChange(document)
            // Typing also changes the tabs; only the list and the active tab are remembered.
            if !isSwitchingFolders,
               oldValue.documents.map(\.url) != openTabs.documents.map(\.url) || oldValue.active?.url != openTabs.active?.url {
                saveTabSession()
            }
        }
    }
    /// Whether the scratchpad is showing instead of the active file tab.
    private(set) var isScratchpadActive = false {
        didSet {
            if isScratchpadActive != oldValue { json.documentDidChange(document) }
        }
    }
    /// Throwaway text that is never saved, restored or counted as unsaved changes.
    private(set) var scratchpadText = ""
    /// Changes on every copy of the scratchpad, so the bar can confirm it.
    private(set) var scratchpadCopyID: UUID?
    /// The scratchpad's editor identity, stable so it keeps its own undo history.
    let scratchpadID = UUID()
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
    @ObservationIgnored private let tabSessions: TabSessionStore
    /// The latest editor selection of each open tab, for the tab session.
    @ObservationIgnored private var editorSelections: [UUID: NSRange] = [:]
    /// Remembered selections of restored tabs, put back when each tab is first shown.
    @ObservationIgnored private var pendingSelections: [UUID: NSRange] = [:]
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
        isScratchpadActive = false
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

    /// Edit › Find in Folder (⇧⌘F): shows the search in the sidebar and focuses its field.
    func showFolderSearch() {
        sidebarMode = .search
        searchFocusRequest = UUID()
    }

    // MARK: Scratchpad

    func showScratchpad() {
        isScratchpadActive = true
        syncSelectionWithActiveTab()
    }

    /// Shows the scratchpad, or goes back to the last file tab when it's already showing.
    func toggleScratchpad() {
        guard isScratchpadActive else {
            showScratchpad()
            return
        }
        guard let lastTab = openTabs.active else { return }
        activateTab(lastTab.id)
    }

    func updateScratchpadText(_ text: String) {
        scratchpadText = text
    }

    /// Empties the scratchpad; the editor applies it as an ordinary edit, so Undo brings the text back.
    func clearScratchpad() {
        scratchpadText = ""
    }

    func copyScratchpad(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(scratchpadText, forType: .string)
        scratchpadCopyID = UUID()
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
        refreshFileIndex()
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
    func reveal(_ range: NSRange, focusesEditor: Bool, highlights: Bool = true) {
        revealRequest = RevealRequest(range: range, focusesEditor: focusesEditor, highlights: highlights)
    }

    // MARK: Tab session

    /// The editor reports each tab's selection, so it can be restored when the folder reopens.
    func noteSelection(_ range: NSRange, in documentID: UUID) {
        editorSelections[documentID] = range
        pendingSelections[documentID] = nil
    }

    /// Remembers the folder's tabs, active tab and selections. Also called when the window closes
    /// and the app quits, because selection changes alone don't save.
    func saveTabSession() {
        guard let rootURL else { return }
        let paths = Dictionary(uniqueKeysWithValues: tabs.compactMap { document in
            document.url.components(below: rootURL).map { (document.id, $0.joined(separator: "/")) }
        })
        let selections = Dictionary(uniqueKeysWithValues: paths.compactMap { id, path in
            (editorSelections[id] ?? pendingSelections[id]).map { (path, $0) }
        })
        let session = TabSession(
            files: tabs.compactMap { paths[$0.id] },
            activeFile: openTabs.active.flatMap { paths[$0.id] },
            selections: selections
        )
        tabSessions.save(session, for: rootURL)
    }

    /// Reopens the folder's remembered tabs; files that are gone are skipped.
    private func restoreTabSession(for folder: URL) {
        guard let session = tabSessions.session(for: folder) else { return }
        var restored = DocumentTabs.empty
        var activeID: UUID?
        for path in session.files {
            let url = folder.appending(path: path, directoryHint: .notDirectory)
            guard fileService.exists(url) else { continue }
            do throws(AppError) {
                let document = OpenDocument(url: url, text: try fileService.read(url))
                restored = restored.opening(document)
                pendingSelections[document.id] = session.selections[path]
                if path == session.activeFile { activeID = document.id }
            } catch {
                Self.logger.error("Could not reopen a tab: \(String(describing: error))")
            }
        }
        openTabs = activeID.map(restored.activating) ?? restored
        syncSelectionWithActiveTab()
        revealPendingSelection()
    }

    /// Puts back the remembered selection of the active tab the first time it shows.
    private func revealPendingSelection() {
        guard let document, let range = pendingSelections.removeValue(forKey: document.id) else { return }
        reveal(range, focusesEditor: false, highlights: false)
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
        rootURL = url
        childrenByFolder = [url: items]
        expandedFolders = []
        openTabs = .empty
        editorSelections = [:]
        pendingSelections = [:]
        selection = nil
        restoreTabSession(for: url)
        isSwitchingFolders = false
        fileIndex = []
        recentFiles = []
        search.reset()
        refreshFileIndex()
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
        isScratchpadActive = false
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
