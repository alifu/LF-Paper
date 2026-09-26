//
//  GitPack.swift
//  LF-Paper
//

import Foundation

/// One pack file and its version 2 index: finds objects by name and reads them, following deltas.
nonisolated struct GitPack {
    private static let indexMagic: [UInt8] = [0xFF, 0x74, 0x4F, 0x63] // "\377tOc"
    private static let indexVersion: UInt32 = 2
    private static let fanoutOffset = 8
    private static let fanoutCount = 256
    private static let largeOffsetFlag: UInt32 = 0x8000_0000
    /// Deeper delta chains than this are treated as damage rather than followed forever.
    private static let maximumDeltaDepth = 64

    private enum PackType {
        static let offsetDelta: UInt8 = 6
        static let referenceDelta: UInt8 = 7
    }

    private let index: Data
    private let pack: Data
    private let objectCount: Int

    /// Memory-maps the pack and its index, so only the parts that are read are loaded.
    init(indexURL: URL) throws(GitError) {
        let packURL = indexURL.deletingPathExtension().appendingPathExtension("pack")
        do {
            index = try Data(contentsOf: indexURL, options: .alwaysMapped)
            pack = try Data(contentsOf: packURL, options: .alwaysMapped)
        } catch {
            throw .corrupt("unreadable pack \(indexURL.lastPathComponent)")
        }
        guard index.count >= Self.fanoutOffset + Self.fanoutCount * 4,
              Array(index.prefix(4)) == Self.indexMagic,
              Self.uint32(in: index, at: 4) == Self.indexVersion
        else { throw .corrupt("unsupported pack index \(indexURL.lastPathComponent)") }
        objectCount = Int(Self.uint32(in: index, at: Self.fanoutOffset + (Self.fanoutCount - 1) * 4))
        // Names, checksums and offsets for every object must fit, so lookups never read past the end.
        let tablesSize = objectCount * (GitObjectID.byteCount + 4 + 4)
        guard index.count >= Self.fanoutOffset + Self.fanoutCount * 4 + tablesSize else {
            throw .corrupt("pack index \(indexURL.lastPathComponent) is truncated")
        }
    }

    /// The object's offset in the pack, or `nil` if this pack doesn't have it.
    func offset(of id: GitObjectID) -> Int? {
        let first = Int(id.bytes[0])
        var low = first == 0 ? 0 : Int(Self.uint32(in: index, at: Self.fanoutOffset + (first - 1) * 4))
        var high = Int(Self.uint32(in: index, at: Self.fanoutOffset + first * 4))
        let namesOffset = Self.fanoutOffset + Self.fanoutCount * 4
        while low < high {
            let middle = (low + high) / 2
            let start = index.startIndex + namesOffset + middle * GitObjectID.byteCount
            let name = index[start..<(start + GitObjectID.byteCount)]
            if name.elementsEqual(id.bytes) {
                return packOffset(at: middle)
            }
            if name.lexicographicallyPrecedes(id.bytes) { low = middle + 1 } else { high = middle }
        }
        return nil
    }

    /// Reads the object at `offset`. `resolveBase` finds the base of a delta that names it by id,
    /// which can live in another pack or loose.
    func object(at offset: Int, resolveBase: (GitObjectID) throws(GitError) -> GitObject) throws(GitError) -> GitObject {
        try object(at: offset, depth: 0, resolveBase: resolveBase)
    }

    private func object(at offset: Int, depth: Int, resolveBase: (GitObjectID) throws(GitError) -> GitObject) throws(GitError) -> GitObject {
        guard depth <= Self.maximumDeltaDepth else { throw .corrupt("delta chain is too deep") }
        var reader = ByteReader(pack, position: offset)
        let (type, size) = try Self.readHeader(&reader)

        switch type {
        case PackType.offsetDelta:
            let distance = try Self.readOffsetDistance(&reader)
            guard distance > 0, distance <= offset else { throw .corrupt("delta base is outside the pack") }
            let delta = try Zlib.inflate(pack, from: reader.position, expectedSize: size)
            let base = try object(at: offset - distance, depth: depth + 1, resolveBase: resolveBase)
            return GitObject(kind: base.kind, data: try GitDelta.apply(delta, to: base.data))
        case PackType.referenceDelta:
            guard let baseID = GitObjectID(bytes: try reader.readBytes(GitObjectID.byteCount)) else {
                throw .corrupt("delta base name is damaged")
            }
            let delta = try Zlib.inflate(pack, from: reader.position, expectedSize: size)
            let base = try resolveBase(baseID)
            return GitObject(kind: base.kind, data: try GitDelta.apply(delta, to: base.data))
        default:
            guard let kind = GitObject.Kind(packType: type) else { throw .corrupt("unknown object type \(type) in pack") }
            return GitObject(kind: kind, data: try Zlib.inflate(pack, from: reader.position, expectedSize: size))
        }
    }

    /// Type in bits 4–6 of the first byte; size in its low 4 bits, then 7 bits per following byte.
    private static func readHeader(_ reader: inout ByteReader) throws(GitError) -> (type: UInt8, size: Int) {
        var byte = try reader.readByte()
        let type = (byte >> 4) & 0x07
        var size = Int(byte & 0x0F)
        var shift = 4
        while byte & 0x80 != 0 {
            byte = try reader.readByte()
            guard shift < 63 else { throw .corrupt("object size is too large") }
            size |= Int(byte & 0x7F) << shift
            shift += 7
        }
        return (type, size)
    }

    /// The distance back to an offset-delta's base, in git's big-endian "+1 per continuation" form.
    private static func readOffsetDistance(_ reader: inout ByteReader) throws(GitError) -> Int {
        var byte = try reader.readByte()
        var distance = Int(byte & 0x7F)
        while byte & 0x80 != 0 {
            byte = try reader.readByte()
            guard distance < Int.max >> 8 else { throw .corrupt("delta offset is too large") }
            distance = ((distance + 1) << 7) | Int(byte & 0x7F)
        }
        return distance
    }

    private func packOffset(at position: Int) -> Int? {
        let crcOffset = Self.fanoutOffset + Self.fanoutCount * 4 + objectCount * GitObjectID.byteCount
        let offsetsOffset = crcOffset + objectCount * 4
        let value = Self.uint32(in: index, at: offsetsOffset + position * 4)
        guard value & Self.largeOffsetFlag != 0 else { return Int(value) }
        let largeOffsetsOffset = offsetsOffset + objectCount * 4
        let large = largeOffsetsOffset + Int(value & ~Self.largeOffsetFlag) * 8
        guard large + 8 <= index.count else { return nil }
        return Int(Self.uint32(in: index, at: large)) << 32 | Int(Self.uint32(in: index, at: large + 4))
    }

    private static func uint32(in data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        let start = data.startIndex + offset
        return data[start..<(start + 4)].reduce(0) { $0 << 8 | UInt32($1) }
    }
}
