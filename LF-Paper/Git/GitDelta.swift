//
//  GitDelta.swift
//  LF-Paper
//

import Foundation

/// Rebuilds an object stored in a pack as a delta: copy ranges of the base object, insert new bytes.
nonisolated enum GitDelta {
    /// A copy instruction with a size of 0 means this many bytes.
    private static let defaultCopySize = 0x10000

    static func apply(_ delta: Data, to base: Data) throws(GitError) -> Data {
        var reader = ByteReader(delta)
        let baseSize = try reader.readSize()
        let resultSize = try reader.readSize()
        guard baseSize == base.count else { throw .corrupt("delta expects a \(baseSize)-byte base, got \(base.count)") }

        var result = Data()
        result.reserveCapacity(resultSize)
        while !reader.isAtEnd {
            let instruction = try reader.readByte()
            if instruction & 0x80 != 0 {
                var offset = 0
                var size = 0
                for bit in 0..<4 where instruction & (1 << bit) != 0 {
                    offset |= Int(try reader.readByte()) << (8 * bit)
                }
                for bit in 0..<3 where instruction & (1 << (4 + bit)) != 0 {
                    size |= Int(try reader.readByte()) << (8 * bit)
                }
                if size == 0 { size = defaultCopySize }
                guard offset + size <= base.count else { throw .corrupt("delta copies past the end of its base") }
                result.append(base[(base.startIndex + offset)..<(base.startIndex + offset + size)])
            } else if instruction != 0 {
                result.append(try reader.readBytes(Int(instruction)))
            } else {
                throw .corrupt("delta has a reserved instruction")
            }
        }
        guard result.count == resultSize else { throw .corrupt("delta produced \(result.count) bytes, expected \(resultSize)") }
        return result
    }
}

/// Reads bytes and git's variable-length numbers from the front of some data.
nonisolated struct ByteReader {
    private let data: Data
    private(set) var position: Int

    init(_ data: Data, position: Int = 0) {
        self.data = data
        self.position = position
    }

    var isAtEnd: Bool { position >= data.count }

    mutating func readByte() throws(GitError) -> UInt8 {
        guard position < data.count else { throw .corrupt("data ends early") }
        defer { position += 1 }
        return data[data.startIndex + position]
    }

    mutating func readBytes(_ count: Int) throws(GitError) -> Data {
        guard count >= 0, position + count <= data.count else { throw .corrupt("data ends early") }
        defer { position += count }
        return data[(data.startIndex + position)..<(data.startIndex + position + count)]
    }

    /// A little-endian number in 7-bit groups; the high bit says another byte follows.
    mutating func readSize() throws(GitError) -> Int {
        var value = 0
        var shift = 0
        while true {
            let byte = try readByte()
            guard shift < 63 else { throw .corrupt("number is too large") }
            value |= Int(byte & 0x7F) << shift
            shift += 7
            if byte & 0x80 == 0 { return value }
        }
    }
}
