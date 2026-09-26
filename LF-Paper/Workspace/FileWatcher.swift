//
//  FileWatcher.swift
//  LF-Paper
//

import CoreServices
import Foundation

/// Watches a folder and everything inside it with FSEvents.
/// `onChange` runs on a background queue shortly after changes settle.
nonisolated final class FileWatcher: @unchecked Sendable {
    // @unchecked: `stream` is only touched in init and deinit.
    private static let latency: CFTimeInterval = 0.3

    private let stream: FSEventStreamRef
    private let queue: DispatchQueue

    /// Returns `nil` if FSEvents can't watch the folder.
    init?(url: URL, onChange: @escaping @Sendable () -> Void) {
        let handler = ChangeHandler(onChange)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(handler).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<ChangeHandler>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<ChangeHandler>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<ChangeHandler>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [url.path(percentEncoded: false)] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
        ) else {
            return nil
        }

        let queue = DispatchQueue(label: "AppWork.LF-Paper.FileWatcher")
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        self.stream = stream
        self.queue = queue
    }

    deinit {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

/// Retained by the FSEvents stream itself, so callbacks never outlive it.
private nonisolated final class ChangeHandler: Sendable {
    let onChange: @Sendable () -> Void

    init(_ onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }
}
