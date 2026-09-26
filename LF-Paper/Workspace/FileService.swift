//
//  FileService.swift
//  LF-Paper
//

import Foundation

/// File-system operations used by the workspace. Every failure is reported as an `AppError`.
nonisolated protocol FileService: Sendable {
    /// Folders first, then supported files, each group in Finder order.
    func contents(of folder: URL, includeHidden: Bool) throws(AppError) -> [FileItem]
    func read(_ file: URL) throws(AppError) -> String
    func write(_ text: String, to file: URL) throws(AppError)
    func createFile(named name: String, in folder: URL) throws(AppError) -> URL
    func createFolder(named name: String, in folder: URL) throws(AppError) -> URL
    /// Returns the item's new URL.
    func rename(_ item: URL, to newName: String) throws(AppError) -> URL
    func moveToTrash(_ item: URL) throws(AppError)
    func exists(_ item: URL) -> Bool
}
