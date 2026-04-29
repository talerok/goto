import Foundation

/// Manages the address bar text, autocomplete suggestions, and focus state.
@Observable
@MainActor
final class AddressBarState {
    /// The text currently displayed in the address bar.
    var text = ""

    /// Whether the address bar should grab focus (set by ⌘L, cleared after focus acquired).
    var wantsFocus = false

    /// Whether the address bar text field currently has keyboard focus.
    var isFocused = false

    var suggestions: [URL] = []
    var selectedSuggestionIndex: Int?
    var showSuggestions = false
    private var suggestionTask: Task<Void, Never>?

    /// Sync the displayed text to a new path (called after navigation).
    func syncToPath(_ path: String) {
        text = path
        dismissSuggestions()
    }

    /// Request focus + select all (⌘L).
    func focusAndSelectAll() {
        wantsFocus = true
    }

    /// Revert text to the given current path (Esc).
    func revert(to currentPath: String) {
        text = currentPath
        dismissSuggestions()
    }

    func dismissSuggestions() {
        suggestions = []
        showSuggestions = false
        selectedSuggestionIndex = nil
        suggestionTask?.cancel()
    }

    /// Update autocomplete suggestions based on the current text.
    func updateSuggestions(relativeTo currentDirectory: URL) {
        suggestionTask?.cancel()
        suggestionTask = Task {
            let text = text
            guard !text.isEmpty else {
                dismissSuggestions()
                return
            }

            guard let resolved = PathResolver.resolve(text, relativeTo: currentDirectory) else {
                dismissSuggestions()
                return
            }

            let resolvedPath = resolved.path(percentEncoded: false)
            let isTrailingSlash = text.hasSuffix("/")
            let parentURL: URL
            let prefix: String

            if isTrailingSlash || FileSystemService.isDirectory(resolvedPath) {
                parentURL = resolved
                prefix = ""
            } else {
                parentURL = resolved.deletingLastPathComponent()
                prefix = resolved.lastPathComponent
            }

            guard !Task.isCancelled else { return }
            let dirs = await FileSystemService.listSubdirectories(at: parentURL)
            guard !Task.isCancelled else { return }

            let filtered: [URL]
            if prefix.isEmpty {
                filtered = dirs
            } else {
                filtered = dirs.filter {
                    $0.lastPathComponent.localizedCaseInsensitiveContains(prefix)
                }
            }

            let sorted = filtered.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }

            suggestions = Array(sorted.prefix(50))
            showSuggestions = !suggestions.isEmpty
            selectedSuggestionIndex = nil
        }
    }

    /// Tab completion: complete to longest common prefix, or full path if single match.
    func tabComplete() {
        guard !suggestions.isEmpty else { return }

        if suggestions.count == 1 {
            let match = suggestions[0]
            let completed = match.path(percentEncoded: false)
            text = completed.hasSuffix("/") ? completed : completed + "/"
        } else {
            let names = suggestions.map { $0.lastPathComponent }
            guard let lcp = longestCommonPrefix(names), !lcp.isEmpty else { return }
            let parent = suggestions[0].deletingLastPathComponent().path(percentEncoded: false)
            let separator = parent.hasSuffix("/") ? "" : "/"
            text = parent + separator + lcp
        }

        showSuggestions = false
        selectedSuggestionIndex = nil
    }

    func selectPreviousSuggestion() {
        guard !suggestions.isEmpty else { return }
        showSuggestions = true
        if let idx = selectedSuggestionIndex {
            selectedSuggestionIndex = idx > 0 ? idx - 1 : suggestions.count - 1
        } else {
            selectedSuggestionIndex = suggestions.count - 1
        }
    }

    func selectNextSuggestion() {
        guard !suggestions.isEmpty else { return }
        showSuggestions = true
        if let idx = selectedSuggestionIndex {
            selectedSuggestionIndex = idx < suggestions.count - 1 ? idx + 1 : 0
        } else {
            selectedSuggestionIndex = 0
        }
    }

    func acceptSelectedSuggestion() {
        guard let idx = selectedSuggestionIndex, suggestions.indices.contains(idx) else { return }
        let selected = suggestions[idx]
        let completed = selected.path(percentEncoded: false)
        text = completed.hasSuffix("/") ? completed : completed + "/"
        showSuggestions = false
        selectedSuggestionIndex = nil
    }

    private func longestCommonPrefix(_ strings: [String]) -> String? {
        guard let first = strings.first else { return nil }
        var prefix = first.lowercased()
        for s in strings.dropFirst() {
            let lower = s.lowercased()
            while !lower.hasPrefix(prefix) && !prefix.isEmpty {
                prefix.removeLast()
            }
        }
        guard !prefix.isEmpty else { return nil }
        return String(first.prefix(prefix.count))
    }
}
