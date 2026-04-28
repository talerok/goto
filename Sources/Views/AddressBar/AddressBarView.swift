import SwiftUI

/// Always-visible address bar. Autocomplete overlay is handled by ContentView.
struct AddressBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            AddressTextField(
                text: Binding(
                    get: { appState.addressBar.text },
                    set: { appState.addressBar.text = $0 }
                ),
                wantsFocus: Binding(
                    get: { appState.addressBar.wantsFocus },
                    set: { appState.addressBar.wantsFocus = $0 }
                ),
                isFocused: Binding(
                    get: { appState.addressBar.isFocused },
                    set: { appState.addressBar.isFocused = $0 }
                ),
                onCommit: commitNavigation,
                onCancel: {
                    appState.addressBar.revert(
                        to: appState.navigation.currentDirectory.path(percentEncoded: false))
                    appState.addressBar.dismissSuggestions()
                    DispatchQueue.main.async {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
                },
                onTab: {
                    if appState.addressBar.selectedSuggestionIndex != nil {
                        appState.addressBar.acceptSelectedSuggestion()
                    } else {
                        appState.addressBar.tabComplete()
                    }
                    appState.addressBar.updateSuggestions(relativeTo: appState.navigation.currentDirectory)
                },
                onArrowUp: {
                    appState.addressBar.selectPreviousSuggestion()
                },
                onArrowDown: {
                    appState.addressBar.selectNextSuggestion()
                },
                onTextChange: { _ in
                    appState.addressBar.updateSuggestions(relativeTo: appState.navigation.currentDirectory)
                }
            )
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(appState.addressBar.isFocused ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1.5)
        )
    }

    private func commitNavigation() {
        // If a suggestion is highlighted, accept it and stay in edit mode
        if appState.addressBar.selectedSuggestionIndex != nil {
            appState.addressBar.acceptSelectedSuggestion()
            appState.addressBar.updateSuggestions(relativeTo: appState.navigation.currentDirectory)
            return
        }

        let text = appState.addressBar.text
        guard let resolved = PathResolver.resolve(
            text, relativeTo: appState.navigation.currentDirectory) else { return }

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: resolved.path(percentEncoded: false), isDirectory: &isDir)

        if !exists || !isDir.boolValue {
            NSSound.beep()
            return
        }

        appState.addressBar.dismissSuggestions()
        Task { await appState.navigateFromAddressBar(to: resolved) }
    }
}
