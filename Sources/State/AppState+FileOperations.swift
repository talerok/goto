import AppKit

// MARK: - File Operations

extension AppState {

    /// Open the selected items. Directories navigate (first one only), files open with default app.
    func openSelectedItems() {
        let selected = selectedFileItems
        guard !selected.isEmpty else { return }

        // Open all files with their default apps.
        let files = selected.filter { !$0.isDirectory }
        for file in files {
            FileSystemService.open(file.url)
        }

        // Navigate to the first selected directory (navigating multiple would race).
        if let firstDir = selected.first(where: \.isDirectory) {
            Task { await navigate(to: firstDir.url) }
        }
    }

    // MARK: - Trash

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
        await loadCurrentDirectory()
        if !failures.isEmpty {
            directory.error = "Failed to trash \(failures.count) item(s)."
        }
    }

    /// Confirm and execute the pending trash.
    func confirmTrash() {
        let items = pendingTrashItems
        pendingTrashItems = []
        showTrashConfirmation = false
        Task { await performTrash(items) }
    }

    // MARK: - Rename

    func startRenaming(_ item: FileItem) {
        cancelRename()          // reset stale state (e.g. after Escape via abortEditing)
        renamingItem = item
        renameText = item.name
    }

    func commitRename() {
        guard let item = renamingItem else { return }
        let newName = renameText.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != item.name, !newName.contains("/") else {
            cancelRename()
            return
        }

        let destination = item.url.deletingLastPathComponent().appending(path: newName)
        Task {
            var renameError: String?
            do {
                try await FileSystemService.rename(item.url, to: destination)
            } catch {
                renameError = "Rename failed: \(error.localizedDescription)"
            }
            cancelRename()
            await loadCurrentDirectory()
            if let renameError {
                directory.error = renameError
            } else {
                // Select the renamed item
                selection = [destination.path(percentEncoded: false)]
            }
        }
    }

    func cancelRename() {
        renamingItem = nil
        renameText = ""
    }

    // MARK: - Copy / Paste

    func copySelectedItems() {
        let urls = selectedFileItems.map(\.url) as [NSURL]
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls)
    }

    func pasteItems() {
        guard let urls = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return }

        let destination = navigation.currentDirectory
        Task {
            var failCount = 0
            for url in urls {
                let dest = FileSystemService.uniqueDestination(for: url, in: destination)
                do {
                    try await FileSystemService.copyFile(from: url, to: dest)
                } catch {
                    failCount += 1
                }
            }
            await loadCurrentDirectory()
            if failCount > 0 {
                directory.error = "Paste failed for \(failCount) item\(failCount == 1 ? "" : "s")."
            }
        }
    }

    // MARK: - Drag & Drop

    /// Handle files dropped from NSItemProviders (used by SwiftUI .onDrop on empty view).
    func dropItems(providers: [NSItemProvider], to destination: URL, asCopy: Bool = false) {
        Task {
            let urls = await loadURLs(from: providers)
            dropItems(urls: urls, to: destination, asCopy: asCopy)
        }
    }

    /// Handle files dropped as URLs (used by NSTableView drag & drop).
    func dropItems(urls: [URL], to destination: URL, asCopy: Bool = false) {
        guard !urls.isEmpty else { return }
        Task {
            var failCount = 0
            for url in urls {
                guard url != destination,
                      url.deletingLastPathComponent() != destination else { continue }
                let dest = FileSystemService.uniqueDestination(for: url, in: destination)
                do {
                    if asCopy {
                        try await FileSystemService.copyFile(from: url, to: dest)
                    } else {
                        try await FileSystemService.rename(url, to: dest)
                    }
                } catch {
                    failCount += 1
                }
            }
            await loadCurrentDirectory()
            if failCount > 0 {
                let op = asCopy ? "Copy" : "Move"
                directory.error = "\(op) failed for \(failCount) item\(failCount == 1 ? "" : "s")."
            }
        }
    }

    private func loadURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            guard provider.canLoadObject(ofClass: NSURL.self) else { continue }
            if let url = await withCheckedContinuation({ continuation in
                _ = provider.loadObject(ofClass: NSURL.self) { reading, _ in
                    continuation.resume(returning: reading as? URL)
                }
            }) {
                urls.append(url)
            }
        }
        return urls
    }
}
