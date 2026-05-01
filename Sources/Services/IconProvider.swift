import AppKit

private let iconDisplaySize = NSSize(width: 18, height: 18)

/// Provides file/folder icons with caching.
@MainActor
final class IconProvider {
    /// Shared singleton.
    private static let shared = IconProvider()

    /// Cache keyed by extension (files) or full path (directories, special items).
    private var cache: [String: NSImage] = [:]
    private static let maxCacheSize = 500

    /// Get the icon for a file item. Returns a cached icon if available.
    static func icon(for item: FileItem) -> NSImage {
        shared.getIcon(for: item)
    }

    private func getIcon(for item: FileItem) -> NSImage {
        let cacheKey = cacheKey(for: item)

        if let cached = cache[cacheKey] {
            return cached
        }

        // Evict if cache grows too large — keep extension-based entries (shared), drop path-based
        if cache.count > Self.maxCacheSize {
            cache = cache.filter { $0.key.hasPrefix("ext:") }
        }

        let path = item.url.path(percentEncoded: false)
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = iconDisplaySize
        cache[cacheKey] = icon
        return icon
    }

    private func cacheKey(for item: FileItem) -> String {
        if item.isDirectory {
            return "dir:" + item.url.path(percentEncoded: false)
        } else {
            let ext = item.url.pathExtension.lowercased()
            return "ext:" + (ext.isEmpty ? "__none__" : ext)
        }
    }
}
