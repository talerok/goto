import AppKit

/// Encapsulates all file system operations. All methods are async and run off the main thread.
enum FileSystemService {

    private static let resourceKeys: [URLResourceKey] = [
        .nameKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .isDirectoryKey,
        .isHiddenKey,
        .isSymbolicLinkKey,
    ]

    /// List the contents of a directory.
    /// - Parameters:
    ///   - url: The directory URL to enumerate.
    ///   - showHidden: Whether to include hidden files.
    /// - Returns: An array of `FileItem` for each entry in the directory.
    static func listDirectory(at url: URL, showHidden: Bool) async throws -> [FileItem] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let contents = try FileManager.default.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: resourceKeys,
                        options: showHidden ? [] : [.skipsHiddenFiles]
                    )

                    let items = contents.compactMap { itemURL -> FileItem? in
                        guard let values = try? itemURL.resourceValues(
                            forKeys: Set(resourceKeys))
                        else {
                            return nil
                        }

                        let name = values.name ?? itemURL.lastPathComponent
                        let isDirectory = values.isDirectory ?? false
                        let isHidden = values.isHidden ?? false
                        let isSymlink = values.isSymbolicLink ?? false
                        let size: Int64? = isDirectory ? nil : values.fileSize.map(Int64.init)
                        let dateModified = values.contentModificationDate

                        return FileItem(
                            id: itemURL.path(percentEncoded: false),
                            url: itemURL,
                            name: name,
                            isDirectory: isDirectory,
                            isHidden: isHidden,
                            isSymlink: isSymlink,
                            size: size,
                            dateModified: dateModified
                        )
                    }

                    continuation.resume(returning: items)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// List only subdirectories of a given directory (for autocomplete).
    static func listSubdirectories(at url: URL) async -> [URL] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let contents = try FileManager.default.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    )

                    let dirs = contents.filter { itemURL in
                        let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                        return isDir
                    }

                    continuation.resume(returning: dirs)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    /// Move items to the Trash.
    /// - Parameter urls: File URLs to trash.
    /// - Returns: URLs that failed to be trashed, along with their errors.
    static func moveToTrash(_ urls: [URL]) async -> [(URL, any Error)] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var failures: [(URL, any Error)] = []
                for url in urls {
                    do {
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    } catch {
                        failures.append((url, error))
                    }
                }
                continuation.resume(returning: failures)
            }
        }
    }

    /// Rename (move) a file or directory.
    static func rename(_ url: URL, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try FileManager.default.moveItem(at: url, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Open a file or directory with the default application.
    @MainActor
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Open a file with a user-chosen application via the system "Open With" panel.
    @MainActor
    static func openWith(_ url: URL) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let appURL = panel.url else { return }

        NSWorkspace.shared.open(
            [url],
            withApplicationAt: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    /// Reveal a file in Finder.
    @MainActor
    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Copy a file's POSIX path to the clipboard.
    @MainActor
    static func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path(percentEncoded: false), forType: .string)
    }

    /// Show the Get Info panel for a file (via Finder AppleScript).
    @MainActor
    static func showGetInfo(_ url: URL) {
        let escaped = url.path(percentEncoded: false)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
            tell application "Finder"
                activate
                open information window of (POSIX file "\(escaped)" as alias)
            end tell
            """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    /// Copy a file or directory to a destination.
    static func copyFile(from source: URL, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try FileManager.default.copyItem(at: source, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Generate a unique destination path, appending " 2", " 3", etc. if the name already exists.
    static func uniqueDestination(for source: URL, in directory: URL) -> URL {
        let name = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var dest = directory.appending(path: source.lastPathComponent)
        var counter = 2
        let fm = FileManager.default

        while fm.fileExists(atPath: dest.path(percentEncoded: false)) {
            let newName = ext.isEmpty ? "\(name) \(counter)" : "\(name) \(counter).\(ext)"
            dest = directory.appending(path: newName)
            counter += 1
        }
        return dest
    }

    /// Quick check whether a path points to a directory.
    static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}
