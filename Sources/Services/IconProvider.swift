import AppKit

/// Provides file/folder icons with caching. Icons are loaded off the main thread.
actor IconProvider {
    /// Shared singleton.
    private static let shared = IconProvider()

    /// Cache keyed by extension (files) or full path (directories, special items).
    private var cache: [String: NSImage] = [:]

    /// Get the icon for a file item. Returns a cached icon if available.
    static func icon(for item: FileItem) async -> NSImage {
        await shared.getIcon(for: item)
    }

    private func getIcon(for item: FileItem) async -> NSImage {
        let cacheKey: String
        if item.isDirectory {
            cacheKey = "dir:" + item.url.path(percentEncoded: false)
        } else {
            let ext = item.url.pathExtension.lowercased()
            cacheKey = "ext:" + (ext.isEmpty ? "__none__" : ext)
        }

        if let cached = cache[cacheKey] {
            return cached
        }

        let path = item.url.path(percentEncoded: false)
        let icon = await MainActor.run {
            NSWorkspace.shared.icon(forFile: path)
        }
        icon.size = NSSize(width: 18, height: 18)
        cache[cacheKey] = icon
        return icon
    }
}
