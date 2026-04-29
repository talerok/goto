import Quartz
import SwiftUI

private let typeAheadTimeout: TimeInterval = 0.8

/// Root application state. Coordinates navigation, directory loading, and the address bar.
@Observable
@MainActor
final class AppState {
    let navigation: NavigationState
    let directory = DirectoryState()
    let addressBar = AddressBarState()

    init(startingDirectory: URL? = nil) {
        self.navigation = NavigationState(startingDirectory: startingDirectory)
    }

    /// Currently selected file item IDs (paths).
    var selection: Set<String> = []

    /// Whether a trash confirmation alert is showing.
    var showTrashConfirmation = false

    /// Items pending trash (set before showing confirmation).
    var pendingTrashItems: [FileItem] = []

    /// Item currently being renamed (nil when not renaming).
    var renamingItem: FileItem?

    /// Text in the rename field.
    var renameText = ""

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

    /// Update the Quick Look panel when selection changes while it's open.
    func updateQuickLookIfVisible() {
        guard let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        let urls = selectedFileItems.map(\.url)
        if urls.isEmpty {
            panel.orderOut(nil)
        } else {
            QuickLookCoordinator.shared.update(urls: urls)
        }
    }

    // MARK: - Type-ahead Search

    private var typeAheadBuffer = ""
    private var typeAheadTimer: Timer?

    /// Handle a character typed for type-ahead filename search.
    func typeAhead(character: Character) {
        typeAheadTimer?.invalidate()
        typeAheadBuffer.append(character)

        let bufferLower = typeAheadBuffer.lowercased()
        if let match = directory.items.first(where: {
            $0.name.localizedCaseInsensitiveCompare(typeAheadBuffer) == .orderedSame
                || $0.name.lowercased().hasPrefix(bufferLower)
        }) {
            selection = [match.id]
        }

        typeAheadTimer = Timer.scheduledTimer(withTimeInterval: typeAheadTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.typeAheadBuffer = ""
            }
        }
    }

    /// Reset type-ahead state. Called on directory changes.
    private func resetTypeAhead() {
        typeAheadTimer?.invalidate()
        typeAheadTimer = nil
        typeAheadBuffer = ""
    }

    // MARK: - Navigation

    /// Reload the current directory contents without touching the address bar text.
    func loadCurrentDirectory() async {
        await directory.load(directory: navigation.currentDirectory)
    }

    /// Sync address bar text to the current directory path.
    private func syncAddressBar() {
        addressBar.syncToPath(navigation.currentDirectory.path(percentEncoded: false))
    }

    /// Common state reset when navigating to a different directory.
    private func prepareForNavigation() {
        selection.removeAll()
        resetTypeAhead()
        syncAddressBar()
        startWatching()
    }

    /// Navigate to a directory and load its contents.
    func navigate(to url: URL) async {
        navigation.navigate(to: url)
        prepareForNavigation()
        await loadCurrentDirectory()
    }

    /// Navigate from the address bar (also records in address bar history).
    func navigateFromAddressBar(to url: URL) async {
        navigation.navigateFromAddressBar(to: url)
        prepareForNavigation()
        await loadCurrentDirectory()
    }

    /// Apply a navigation mutation (back/forward/up) and reload.
    private func performNavigation(_ mutation: () -> Void) {
        mutation()
        prepareForNavigation()
        Task { await loadCurrentDirectory() }
    }

    func navigateBack() {
        performNavigation { navigation.goBack() }
    }

    func navigateForward() {
        performNavigation { navigation.goForward() }
    }

    func navigateUp() {
        performNavigation { navigation.goUp() }
    }

    // MARK: - Helpers

    /// Select all items in the current directory.
    func selectAll() {
        selection = Set(directory.items.map(\.id))
    }

    var selectedFileItems: [FileItem] {
        directory.items.filter { selection.contains($0.id) }
    }
}
