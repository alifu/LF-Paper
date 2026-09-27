//
//  WorkspaceModel+Files.swift
//  LF-Paper
//

import Foundation

/// The folder tree in the sidebar, file operations, and keeping open tabs in line with the disk.
extension WorkspaceModel {
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

    // MARK: Tree

    /// Loaded folder contents. Only the root and expanded folders are kept up to date.
    var childrenByFolder: [URL: [FileItem]] { folderTree.childrenByFolder }

    var expandedFolders: Set<URL> { folderTree.expandedFolders }

    func children(of folder: URL) -> [FileItem] {
        folderTree.children(of: folder)
    }

    /// The loaded item at `url`, matched by path so spelling differences
    /// (like a trailing slash) don't matter.
    func item(at url: URL) -> FileItem? {
        folderTree.item(at: url)
    }

    func setExpanded(_ folder: URL, _ isExpanded: Bool) {
        guard isExpanded else {
            folderTree = folderTree.collapsing(folder)
            return
        }
        guard ensureLoaded(folder) else { return }
        folderTree = folderTree.expanding(folder)
    }

    /// Re-reads the root and every expanded folder, dropping anything that disappeared,
    /// and brings the open document in line with the disk.
    func reloadAll() {
        guard rootURL != nil else { return }
        let (reloaded, errors) = folderTree.reloading(using: listFolder)
        errors.forEach(present)
        folderTree = reloaded
        if let selection, !fileService.exists(selection) {
            self.selection = nil
        }
        syncDocumentsWithDisk()
        refreshFileIndex()
    }

    /// Where "New File"/"New Folder" go: the folder itself, or the folder containing the file.
    func targetFolder(for item: FileItem?) -> URL? {
        folderTree.targetFolder(for: item)
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

    // MARK: Private

    private func listFolder(_ folder: URL) throws(AppError) -> [FileItem] {
        try fileService.contents(of: folder, includeHidden: showsHiddenFiles)
    }

    /// Lists `folder` unless it's already loaded. Returns `false` (and presents the error) if it can't be read.
    @discardableResult
    private func ensureLoaded(_ folder: URL) -> Bool {
        guard !folderTree.isLoaded(folder) else { return true }
        do throws(AppError) {
            folderTree = try folderTree.loading(folder, using: listFolder)
            return true
        } catch {
            present(error)
            return false
        }
    }

    private func create(_ newItem: NewItem, in folder: URL) {
        guard ensureLoaded(folder) else { return }
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
                folderTree = folderTree.expanding(folder)
            }
            reloadAll()
            selection = item(at: created)?.url ?? created
        } catch {
            present(error)
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
        guard !document.isNew else { return } // not on disk until it's saved
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
}
