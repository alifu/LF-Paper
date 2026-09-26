//
//  LocalFileService.swift
//  LF-Paper
//

import Foundation

/// `FileService` backed by `FileManager`.
nonisolated struct LocalFileService: FileService {
    private static let listingKeys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]

    private var fileManager: FileManager { .default }

    // MARK: Listing

    func contents(of folder: URL, includeHidden: Bool) throws(AppError) -> [FileItem] {
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: Self.listingKeys,
                options: options
            )
        } catch {
            throw AppError.from(error, url: folder, fallback: AppError.readFailed)
        }
        return urls.compactMap(Self.item(for:)).sorted(by: Self.isOrderedBefore)
    }

    /// Folders become `.folder` (packages like `.app` are skipped); files need a supported extension.
    private static func item(for url: URL) -> FileItem? {
        let values = try? url.resourceValues(forKeys: Set(listingKeys))
        if values?.isDirectory == true {
            return values?.isPackage == true ? nil : FileItem(url: url, kind: .folder)
        }
        return FileKind(fileExtension: url.pathExtension).map { FileItem(url: url, kind: $0) }
    }

    private static func isOrderedBefore(_ lhs: FileItem, _ rhs: FileItem) -> Bool {
        if lhs.isFolder != rhs.isFolder {
            return lhs.isFolder
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    // MARK: Reading and writing

    func read(_ file: URL) throws(AppError) -> String {
        do {
            return try String(contentsOf: file, encoding: .utf8)
        } catch {
            throw AppError.from(error, url: file, fallback: AppError.readFailed)
        }
    }

    func write(_ text: String, to file: URL) throws(AppError) {
        do {
            try Data(text.utf8).write(to: file, options: .atomic)
        } catch {
            throw AppError.from(error, url: file, fallback: AppError.writeFailed)
        }
    }

    // MARK: Creating

    func createFile(named name: String, in folder: URL) throws(AppError) -> URL {
        let file = folder.appending(path: try FileNaming.validate(name), directoryHint: .notDirectory)
        guard !exists(file) else { throw .alreadyExists(file) }
        do {
            try Data().write(to: file, options: .withoutOverwriting)
        } catch {
            throw AppError.from(error, url: file, fallback: AppError.writeFailed)
        }
        return file
    }

    func createFolder(named name: String, in folder: URL) throws(AppError) -> URL {
        let newFolder = folder.appending(path: try FileNaming.validate(name), directoryHint: .isDirectory)
        guard !exists(newFolder) else { throw .alreadyExists(newFolder) }
        do {
            try fileManager.createDirectory(at: newFolder, withIntermediateDirectories: false)
        } catch {
            throw AppError.from(error, url: newFolder, fallback: AppError.writeFailed)
        }
        return newFolder
    }

    // MARK: Renaming and deleting

    func rename(_ item: URL, to newName: String) throws(AppError) -> URL {
        let validName = try FileNaming.validate(newName)
        guard validName != item.lastPathComponent else { return item }

        let hint: URL.DirectoryHint = item.hasDirectoryPath ? .isDirectory : .notDirectory
        let destination = item.deletingLastPathComponent().appending(path: validName, directoryHint: hint)
        // On a case-insensitive disk "note.md" → "Note.md" is the same file, so it "exists" already.
        let isCaseOnlyChange = validName.lowercased() == item.lastPathComponent.lowercased()
        guard isCaseOnlyChange || !exists(destination) else { throw .alreadyExists(destination) }

        do {
            try fileManager.moveItem(at: item, to: destination)
        } catch {
            throw AppError.from(error, url: item, fallback: AppError.writeFailed)
        }
        return destination
    }

    func moveToTrash(_ item: URL) throws(AppError) {
        do {
            try fileManager.trashItem(at: item, resultingItemURL: nil)
        } catch {
            throw AppError.from(error, url: item, fallback: AppError.writeFailed)
        }
    }

    func exists(_ item: URL) -> Bool {
        fileManager.fileExists(atPath: item.path(percentEncoded: false))
    }
}
