//
//  Zlib.swift
//  LF-Paper
//

import Compression
import Foundation

/// Inflates zlib streams, the compression git uses for every object.
nonisolated enum Zlib {
    private static let headerLength = 2
    private static let presetDictionaryFlag: UInt8 = 0x20
    private static let chunkSize = 64 * 1024

    /// Inflates the zlib stream starting at `offset`. Anything after the end of the stream (such as
    /// the next object in a pack) is ignored. `expectedSize` sizes the output buffer when known.
    static func inflate(_ data: Data, from offset: Int = 0, expectedSize: Int? = nil) throws(GitError) -> Data {
        // The Compression framework reads raw DEFLATE, so skip zlib's 2-byte header.
        guard data.count - offset > headerLength else { throw .corrupt("compressed data is too short") }
        let flags = data[data.startIndex + offset + 1]
        guard flags & presetDictionaryFlag == 0 else { throw .corrupt("compressed data uses a preset dictionary") }

        let start = data.startIndex + offset + headerLength
        var output = Data()
        output.reserveCapacity(expectedSize ?? chunkSize)

        let status: compression_status = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else { return COMPRESSION_STATUS_ERROR }
            let streamPointer = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
            defer { streamPointer.deallocate() }
            guard compression_stream_init(streamPointer, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
                return COMPRESSION_STATUS_ERROR
            }
            defer { compression_stream_destroy(streamPointer) }

            let chunk = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
            defer { chunk.deallocate() }
            streamPointer.pointee.src_ptr = base + (start - data.startIndex)
            streamPointer.pointee.src_size = data.endIndex - start
            while true {
                streamPointer.pointee.dst_ptr = chunk
                streamPointer.pointee.dst_size = chunkSize
                let inputBefore = streamPointer.pointee.src_size
                let status = compression_stream_process(streamPointer, 0)
                let produced = chunkSize - streamPointer.pointee.dst_size
                output.append(chunk, count: produced)
                switch status {
                case COMPRESSION_STATUS_OK:
                    // Neither input read nor output written: the stream is cut short or stuck.
                    if produced == 0 && streamPointer.pointee.src_size == inputBefore {
                        return COMPRESSION_STATUS_ERROR
                    }
                case COMPRESSION_STATUS_END:
                    return COMPRESSION_STATUS_END
                default:
                    return COMPRESSION_STATUS_ERROR
                }
            }
        }
        guard status == COMPRESSION_STATUS_END else { throw .corrupt("compressed data is damaged") }
        if let expectedSize, output.count != expectedSize {
            throw .corrupt("inflated \(output.count) bytes, expected \(expectedSize)")
        }
        return output
    }
}
