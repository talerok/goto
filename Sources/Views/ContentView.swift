import SwiftUI

/// Toolbar navigation button with hover highlight.
struct NavButton: View {
    let icon: String
    let help: String
    let disabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering && !disabled ? .white.opacity(0.08) : .clear)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? .tertiary : .secondary)
        .disabled(disabled)
        .help(help)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // Nav buttons + address bar in one row
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    NavButton(icon: "chevron.left", help: "Back (⌘[)",
                              disabled: !appState.navigation.canGoBack) {
                        appState.navigateBack()
                    }
                    NavButton(icon: "chevron.right", help: "Forward (⌘])",
                              disabled: !appState.navigation.canGoForward) {
                        appState.navigateForward()
                    }
                    NavButton(icon: "chevron.up", help: "Enclosing Folder (⌘↑)",
                              disabled: !appState.navigation.canGoUp) {
                        appState.navigateUp()
                    }
                }

                AddressBarView()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()
            FileListView()
        }
        .frame(minWidth: 500, minHeight: 300)
        .overlay(alignment: .top) {
            if appState.addressBar.showSuggestions {
                AutocompletePopover(
                    suggestions: appState.addressBar.suggestions,
                    selectedIndex: appState.addressBar.selectedSuggestionIndex,
                    onSelect: { url in
                        let path = url.path(percentEncoded: false)
                        appState.addressBar.text = path.hasSuffix("/") ? path : path + "/"
                        appState.addressBar.dismissSuggestions()
                        appState.addressBar.updateSuggestions(
                            relativeTo: appState.navigation.currentDirectory)
                    }
                )
                .padding(.horizontal, 10)
                .offset(y: 50)
            }
        }
        .task {
            appState.addressBar.syncToPath(
                appState.navigation.currentDirectory.path(percentEncoded: false))
            await appState.loadCurrentDirectory()
        }
        .onChange(of: appState.directory.showHiddenFiles) {
            Task { await appState.loadCurrentDirectory() }
        }
        .onKeyPress(.space) {
            guard !appState.addressBar.isFocused, appState.renamingItem == nil else { return .ignored }
            appState.toggleQuickLook()
            return .handled
        }
        .onKeyPress(.delete) {
            guard !appState.addressBar.isFocused, appState.renamingItem == nil else { return .ignored }
            appState.trashSelectedItems()
            return .handled
        }
        .onKeyPress(.return) {
            guard !appState.addressBar.isFocused, appState.renamingItem == nil else { return .ignored }
            appState.openSelectedItems()
            return .handled
        }
        .onKeyPress(characters: .letters.union(.decimalDigits).union(.punctuationCharacters).union(.symbols)) { press in
            guard !appState.addressBar.isFocused, appState.renamingItem == nil else { return .ignored }
            guard let char = press.characters.first else { return .ignored }
            appState.typeAhead(character: char)
            return .handled
        }
        .onDisappear {
            appState.stopWatching()
        }
    }
}
