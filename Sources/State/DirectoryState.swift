import Foundation

/// Manages the loaded file items for the current directory, sorting, and hidden file visibility.
@Observable
@MainActor
final class DirectoryState {
    /// The sorted, filtered items currently displayed.
    private(set) var items: [FileItem] = []

    /// Raw items before sorting/filtering, used for re-sort without re-load.
    private var rawItems: [FileItem] = []

    private(set) var isLoading = false
    var error: String?

    var showHiddenFiles = false {
        didSet { applyFilterAndSort() }
    }

    var sort: SortCriteria = .default {
        didSet { applyFilterAndSort() }
    }

    /// Load the contents of a directory.
    func load(directory url: URL) async {
        isLoading = true
        error = nil

        do {
            // Always fetch all items (including hidden) and filter in-memory
            let allItems = try await FileSystemService.listDirectory(at: url, showHidden: true)
            rawItems = allItems
            applyFilterAndSort()
        } catch let err as NSError {
            if err.domain == NSCocoaErrorDomain && err.code == NSFileReadNoPermissionError {
                error = "Permission denied — grant Full Disk Access in System Settings → Privacy & Security."
            } else {
                error = err.localizedDescription
            }
            rawItems = []
            items = []
        }

        isLoading = false
    }

    /// Re-apply the current hidden-file filter and sort criteria to cached raw items.
    func applyFilterAndSort() {
        var filtered = rawItems
        if !showHiddenFiles {
            filtered = filtered.filter { !$0.isHidden }
        }
        items = filtered.sorted(by: sort.comparator)
    }

    /// Toggle sort: if same field, flip direction; if different field, set ascending.
    func toggleSort(for field: SortField) {
        if sort.field == field {
            sort.direction.toggle()
        } else {
            sort = SortCriteria(field: field, direction: .ascending)
        }
    }
}
