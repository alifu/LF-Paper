//
//  GitObject.swift
//  LF-Paper
//

import Foundation

/// Why a file couldn't be read from the repository.
nonisolated enum GitError: Error, Equatable, Sendable {
    /// HEAD doesn't point at a commit yet (a new repository).
    case noCommits
    /// The path isn't a file in the last commit (untracked, deleted, or a folder).
    case fileNotInCommit(String)
    case missingObject(String)
    /// The repository data couldn't be understood.
    case corrupt(String)
}

/// A 20-byte SHA-1 object name.
nonisolated struct GitObjectID: Hashable, Sendable, CustomStringConvertible {
    static let byteCount = 20

    let bytes: [UInt8]

    init?(bytes: some Collection<UInt8>) {
        guard bytes.count == Self.byteCount else { return nil }
        self.bytes = Array(bytes)
    }

    init?(hex: some StringProtocol) {
        let digits = Array(hex.utf8)
        guard digits.count == Self.byteCount * 2 else { return nil }
        var bytes: [UInt8] = []
        for index in stride(from: 0, to: digits.count, by: 2) {
            guard let high = Self.nibble(digits[index]), let low = Self.nibble(digits[index + 1]) else { return nil }
            bytes.append(high << 4 | low)
        }
        self.bytes = bytes
    }

    var description: String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// The first 7 hex digits, as git shows commits.
    var shortDescription: String {
        String(description.prefix(7))
    }

    private static func nibble(_ digit: UInt8) -> UInt8? {
        switch digit {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): digit - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): digit - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): digit - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}

/// An object's type and contents.
nonisolated struct GitObject: Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        case commit, tree, blob, tag

        init?(name: String) {
            switch name {
            case "commit": self = .commit
            case "tree": self = .tree
            case "blob": self = .blob
            case "tag": self = .tag
            default: return nil
            }
        }

        /// The type number used in pack files.
        init?(packType: UInt8) {
            switch packType {
            case 1: self = .commit
            case 2: self = .tree
            case 3: self = .blob
            case 4: self = .tag
            default: return nil
            }
        }
    }

    let kind: Kind
    let data: Data
}
