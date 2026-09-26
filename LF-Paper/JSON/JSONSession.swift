//
//  JSONSession.swift
//  LF-Paper
//

import Foundation
import Observation

/// Keeps the open JSON document parsed in the background: its validity, error, tree and the
/// source range of every value. While the text is invalid, the last valid tree stays available.
@Observable
final class JSONSession {
    enum Status: Equatable {
        /// No JSON document is open.
        case inactive
        /// A newly opened document hasn't been parsed yet.
        case analyzing
        case valid
        case invalid(JSONParseError)
    }

    /// Pause after typing before re-parsing.
    private static let analysisDelay: Duration = .milliseconds(250)

    private(set) var status: Status = .inactive
    /// The most recent successful parse of the current document.
    private(set) var lastValid: JSONDocument?
    /// Increases with every successful parse, so views know when the tree changed.
    private(set) var version = 0

    /// The running analysis; tests await it.
    @ObservationIgnored private(set) var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var documentID: UUID?
    @ObservationIgnored private var analyzedText: String?

    var tree: JSONTreeNode? {
        lastValid.map { JSONTreeNode(root: $0.value) }
    }

    var sourceRanges: [JSONPath: NSRange] {
        lastValid?.sourceRanges ?? [:]
    }

    /// Call whenever the open document changes. Non-JSON documents clear the session.
    func documentDidChange(_ document: OpenDocument?) {
        guard let document, FileKind(fileExtension: document.url.pathExtension) == .json else {
            reset()
            return
        }
        let isNewDocument = document.id != documentID
        guard isNewDocument || document.text != analyzedText else { return } // e.g. saved or renamed
        documentID = document.id
        analyzedText = document.text
        if isNewDocument {
            lastValid = nil
            status = .analyzing
        }

        analysisTask?.cancel()
        let text = document.text
        analysisTask = Task { [weak self] in
            if !isNewDocument {
                try? await Task.sleep(for: Self.analysisDelay) // cancelled sleeps end early; checked below
            }
            guard !Task.isCancelled else { return }
            let result = await Self.analyze(text)
            guard !Task.isCancelled else { return }
            self?.apply(result)
        }
    }

    @concurrent
    private static func analyze(_ text: String) async -> Result<JSONDocument, JSONParseError> {
        do throws(JSONParseError) {
            return .success(try JSONParser.parse(text, recordsSourceRanges: true))
        } catch {
            return .failure(error)
        }
    }

    private func apply(_ result: Result<JSONDocument, JSONParseError>) {
        switch result {
        case .success(let document):
            lastValid = document
            version += 1
            status = .valid
        case .failure(let error):
            status = .invalid(error)
        }
    }

    private func reset() {
        analysisTask?.cancel()
        analysisTask = nil
        documentID = nil
        analyzedText = nil
        lastValid = nil
        status = .inactive
    }
}
