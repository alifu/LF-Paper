//
//  AppErrorTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

struct AppErrorTests {

    private let fileURL = URL(filePath: "/tmp/workspace/notes.md")

    @Test func fileErrorsNameTheAffectedFile() {
        let errors: [AppError] = [
            .fileNotFound(fileURL),
            .accessDenied(fileURL),
            .readFailed(fileURL),
            .writeFailed(fileURL),
            .alreadyExists(fileURL),
        ]

        for error in errors {
            #expect(error.errorDescription?.contains("notes.md") == true, "\(error)")
        }
    }

    @Test func fileErrorsDoNotLeakFullPaths() {
        let error = AppError.readFailed(fileURL)

        #expect(error.errorDescription?.contains("/tmp/workspace") == false)
    }

    @Test func invalidNameExplainsTheName() {
        let error = AppError.invalidName("a/b")

        #expect(error.errorDescription?.contains("a/b") == true)
    }

    @Test func accessDeniedSuggestsReopeningTheFolder() {
        let error = AppError.accessDenied(fileURL)

        #expect(error.recoverySuggestion?.isEmpty == false)
    }

    // MARK: Mapping system errors

    @Test func missingFileErrorsMapToFileNotFound() {
        let error = AppError.from(CocoaError(.fileReadNoSuchFile), url: fileURL, fallback: AppError.readFailed)

        #expect(error == .fileNotFound(fileURL))
    }

    @Test func permissionErrorsMapToAccessDenied() {
        let error = AppError.from(CocoaError(.fileWriteNoPermission), url: fileURL, fallback: AppError.writeFailed)

        #expect(error == .accessDenied(fileURL))
    }

    @Test func existingFileErrorsMapToAlreadyExists() {
        let error = AppError.from(CocoaError(.fileWriteFileExists), url: fileURL, fallback: AppError.writeFailed)

        #expect(error == .alreadyExists(fileURL))
    }

    @Test func unknownErrorsUseTheFallback() {
        let error = AppError.from(URLError(.unknown), url: fileURL, fallback: AppError.writeFailed)

        #expect(error == .writeFailed(fileURL))
    }

    @Test func appErrorsPassThroughUnchanged() {
        let error = AppError.from(AppError.invalidName("x"), url: fileURL, fallback: AppError.readFailed)

        #expect(error == .invalidName("x"))
    }

    @Test func errorsAreEquatableByCaseAndPayload() {
        #expect(AppError.readFailed(fileURL) == AppError.readFailed(fileURL))
        #expect(AppError.readFailed(fileURL) != AppError.writeFailed(fileURL))
    }
}
