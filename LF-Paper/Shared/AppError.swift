//
//  AppError.swift
//  LF-Paper
//

import Foundation

/// User-facing errors. Messages name the file, never its full path.
nonisolated enum AppError: Error, Equatable, Sendable {
    case fileNotFound(URL)
    case accessDenied(URL)
    case readFailed(URL)
    case writeFailed(URL)
    case alreadyExists(URL)
    case invalidName(String)
    /// Compare with Last Commit, for a folder outside any Git repository.
    case notInRepository
    /// The file (by name) isn't in the last commit: untracked, or the repository has no commits.
    case notInLastCommit(String)
    /// The repository couldn't be read (damaged or in a format LF-Paper doesn't read).
    case gitReadFailed(String)
    /// Convert (YAML, CSV) couldn't be done; the text says why.
    case conversionFailed(String)
}

nonisolated extension AppError {
    /// Maps a system error to a user-facing error about `url`.
    /// Unrecognised errors become `fallback(url)`; `AppError`s pass through unchanged.
    static func from(_ error: any Error, url: URL, fallback: (URL) -> AppError) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        guard let cocoaError = error as? CocoaError else {
            return fallback(url)
        }
        switch cocoaError.code {
        case .fileNoSuchFile, .fileReadNoSuchFile:
            return .fileNotFound(url)
        case .fileReadNoPermission, .fileWriteNoPermission:
            return .accessDenied(url)
        case .fileWriteFileExists:
            return .alreadyExists(url)
        default:
            return fallback(url)
        }
    }
}

nonisolated extension AppError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            "“\(url.lastPathComponent)” could not be found."
        case .accessDenied(let url):
            "LF-Paper doesn’t have permission to access “\(url.lastPathComponent)”."
        case .readFailed(let url):
            "“\(url.lastPathComponent)” could not be opened."
        case .writeFailed(let url):
            "“\(url.lastPathComponent)” could not be saved."
        case .alreadyExists(let url):
            "An item named “\(url.lastPathComponent)” already exists."
        case .invalidName(let name):
            "“\(name)” is not a valid file name."
        case .notInRepository:
            "This folder isn’t in a Git repository."
        case .notInLastCommit(let name):
            "“\(name)” isn’t in the last commit."
        case .gitReadFailed(let name):
            "The last commit of “\(name)” could not be read."
        case .conversionFailed(let reason):
            reason
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .fileNotFound:
            "It may have been moved or deleted outside LF-Paper."
        case .accessDenied:
            "Reopen the folder with File › Open Folder to grant access again."
        case .readFailed:
            "Check that the file is a readable text file."
        case .writeFailed:
            "Check that the disk has free space and the file isn’t locked."
        case .alreadyExists:
            "Choose a different name."
        case .invalidName:
            "Names can’t be empty or contain “/” or “:”."
        case .notInRepository:
            "Open the repository’s top folder so LF-Paper can read its history."
        case .notInLastCommit:
            "Commit the file first, or check that it isn’t ignored."
        case .gitReadFailed:
            "The repository may be damaged or use a format LF-Paper can’t read yet."
        case .conversionFailed:
            nil
        }
    }
}
