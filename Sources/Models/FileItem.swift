import AppKit

/// Represents a single file or directory entry in a directory listing.
struct FileItem: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let name: String
    let isDirectory: Bool
    let isHidden: Bool
    let isSymlink: Bool
    let size: Int64?
    let dateModified: Date?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.isHidden == rhs.isHidden &&
        lhs.isSymlink == rhs.isSymlink &&
        lhs.size == rhs.size &&
        lhs.dateModified == rhs.dateModified
    }
}

extension FileItem {
    /// Formatted file size string. Returns "—" for directories.
    @MainActor
    var formattedSize: String {
        guard !isDirectory, let size else { return "—" }
        return Formatters.byteCount.string(fromByteCount: size)
    }

    /// Formatted modification date string.
    @MainActor
    var formattedDate: String {
        guard let dateModified else { return "—" }
        return Formatters.shortDateTime.string(from: dateModified)
    }
}

@MainActor
private enum Formatters {
    static let byteCount: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
