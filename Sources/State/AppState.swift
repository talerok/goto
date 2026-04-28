import SwiftUI

/// Root application state. Coordinates navigation, directory loading, and the address bar.
@Observable
@MainActor
final class AppState {
    let navigation = NavigationState()
    let directory = DirectoryState()
    let addressBar = AddressBarState()

    /// Currently selected file item IDs (paths).
    var selection: Set<String> = []

    /// Whether a trash confirmation alert is showing.
    var showTrashConfirmation = false

    /// Items pending trash (set before showing confirmation).
    var pendingTrashItems: [FileItem] = []

    // MARK: - FSEvents

    private let fsMonitor = FSEventsMonitor()

    /// Start watching the current directory for changes.
    func startWatching() {
        let url = navigation.currentDirectory
        fsMonitor.start(watching: url) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.loadCurrentDirectory()
            }
        }
    }

    /// Stop watching the current directory.
    func stopWatching() {
        fsMonitor.stop()
    }

    // MARK: - Quick Look

    func toggleQuickLook() {
        let urls = selectedFileItems.map(\.url)
        guard !urls.isEmpty else { return }
        QuickLookCoordinator.shared.toggle(urls: urls)
    }

    // MARK: - Type-ahead Search

    private var typeAheadBuffer = ""
    private var typeAheadTimer: Timer?

    /// Handle a character typed for type-ahead filename search.
    func typeAhead(character: Character) {
        typeAheadTimer?.invalidate()
        typeAheadBuffer.append(character)

        // Find the first item whose name starts with the typed prefix (case-insensitive)
        if let match = directory.items.first(where: {
            $0.name.localizedCaseInsensitiveCompare(typeAheadBuffer) == .orderedSame
                || $0.name.lowercased().hasPrefix(typeAheadBuffer.lowercased())
        }) {
            selection = [match.id]
        }

        typeAheadTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.typeAheadBuffer = ""
            }
        }
    }

    // MARK: - Navigation

    /// Reload the current directory contents without touching the address bar text.
    func loadCurrentDirectory() async {
        await directory.load(directory: navigation.currentDirectory)
        startWatching()
    }

    /// Sync address bar text to the current directory path.
    private func syncAddressBar() {
        addressBar.syncToPath(navigation.currentDirectory.path(percentEncoded: false))
    }

    /// Navigate to a directory and load its contents.
    func navigate(to url: URL) async {
        navigation.navigate(to: url)
        selection.removeAll()
        syncAddressBar()
        await loadCurrentDirectory()
    }

    /// Navigate from the address bar (also records in address bar history).
    func navigateFromAddressBar(to url: URL) async {
        navigation.navigateFromAddressBar(to: url)
        selection.removeAll()
        syncAddressBar()
        await loadCurrentDirectory()
    }

    func navigateBack() {
        navigation.goBack()
        selection.removeAll()
        syncAddressBar()
        Task { await loadCurrentDirectory() }
    }

    func navigateForward() {
        navigation.goForward()
        selection.removeAll()
        syncAddressBar()
        Task { await loadCurrentDirectory() }
    }

    func navigateUp() {
        navigation.goUp()
        selection.removeAll()
        syncAddressBar()
        Task { await loadCurrentDirectory() }
    }

    // MARK: - File Operations

    /// Open the selected items. Directories navigate, files open with default app.
    func openSelectedItems() {
        let selected = selectedFileItems
        guard !selected.isEmpty else { return }

        if selected.count == 1, let item = selected.first, item.isDirectory {
            Task { await navigate(to: item.url) }
            return
        }

        for item in selected {
            if item.isDirectory {
                Task { await navigate(to: item.url) }
            } else {
                FileSystemService.open(item.url)
            }
        }
    }

    /// Initiate trash for selected items. Shows confirmation if multiple items are selected.
    func trashSelectedItems() {
        let selected = selectedFileItems
        guard !selected.isEmpty else { return }

        if selected.count > 1 {
            pendingTrashItems = selected
            showTrashConfirmation = true
        } else {
            Task { await performTrash(selected) }
        }
    }

    /// Execute the actual trash operation.
    func performTrash(_ items: [FileItem]) async {
        let failures = await FileSystemService.moveToTrash(items.map(\.url))
        if !failures.isEmpty {
            directory.error = "Failed to trash \(failures.count) item(s)."
        }
        await loadCurrentDirectory()
    }

    /// Confirm and execute the pending trash.
    func confirmTrash() {
        let items = pendingTrashItems
        pendingTrashItems = []
        showTrashConfirmation = false
        Task { await performTrash(items) }
    }

    // MARK: - Rename

    var renamingItem: FileItem?
    var renameText = ""

    func startRenaming(_ item: FileItem) {
        renamingItem = item
        renameText = item.name
    }

    func commitRename() {
        guard let item = renamingItem else { return }
        let newName = renameText.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != item.name else {
            cancelRename()
            return
        }

        let destination = item.url.deletingLastPathComponent().appending(path: newName)
        Task {
            do {
                try await FileSystemService.rename(item.url, to: destination)
            } catch {
                directory.error = "Rename failed: \(error.localizedDescription)"
            }
            cancelRename()
            await loadCurrentDirectory()
        }
    }

    func cancelRename() {
        renamingItem = nil
        renameText = ""
    }

    // MARK: - Helpers

    var selectedFileItems: [FileItem] {
        directory.items.filter { selection.contains($0.id) }
    }
}
