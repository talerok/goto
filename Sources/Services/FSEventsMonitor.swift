import Foundation

private let fsEventsLatency: CFTimeInterval = 0.5

/// Monitors a directory for file system changes using FSEvents.
/// Thread safety: `stream` is only accessed from the main thread (via @MainActor AppState).
/// `onChange` is protected by `lock` since it's written from main thread and read from the FSEvents queue.
final class FSEventsMonitor: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.goto.fsevents", qos: .utility)
    private let lock = NSLock()
    private var onChange: (@Sendable () -> Void)?

    /// Start monitoring a directory.
    /// - Parameters:
    ///   - url: The directory to watch.
    ///   - handler: Called on the FSEvents queue when any change is detected.
    func start(watching url: URL, handler: @escaping @Sendable () -> Void) {
        stop()
        lock.withLock { onChange = handler }

        let path = url.path(percentEncoded: false)
        var context = FSEventStreamContext()
        context.info = Unmanaged.passRetained(self).toOpaque()

        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagUseCFTypes) |
            UInt32(kFSEventStreamCreateFlagFileEvents) |
            UInt32(kFSEventStreamCreateFlagNoDefer)

        guard let stream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            fsEventsLatency,
            flags
        ) else {
            // Balance the passRetained above
            Unmanaged<FSEventsMonitor>.fromOpaque(context.info!).release()
            lock.withLock { onChange = nil }
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    /// Stop monitoring.
    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        lock.withLock { onChange = nil }
        // Balance the passRetained from start()
        Unmanaged.passUnretained(self).release()
    }

    /// Called from the FSEvents callback on `queue`.
    fileprivate func handleEvent() {
        let handler = lock.withLock { onChange }
        handler?()
    }

    deinit {
        // passRetained in start() prevents deallocation while the stream is active.
        // stop() releases the retained reference, allowing deallocation when the
        // last external reference (AppState) drops.
    }
}

private func fsEventsCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let monitor = Unmanaged<FSEventsMonitor>.fromOpaque(info).takeUnretainedValue()
    monitor.handleEvent()
}
