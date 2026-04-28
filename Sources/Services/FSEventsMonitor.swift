import Foundation

/// Monitors a directory for file system changes using FSEvents.
/// Calls the `onChange` handler when changes are detected.
final class FSEventsMonitor: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.goto.fsevents", qos: .utility)
    fileprivate var onChange: (@Sendable () -> Void)?

    /// Start monitoring a directory.
    /// - Parameters:
    ///   - url: The directory to watch.
    ///   - handler: Called when any change is detected in the directory.
    func start(watching url: URL, handler: @escaping @Sendable () -> Void) {
        stop()
        onChange = handler

        let path = url.path(percentEncoded: false)
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

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
            0.5, // latency in seconds
            flags
        ) else { return }

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
        onChange = nil
    }

    deinit {
        stop()
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
    monitor.onChange?()
}
