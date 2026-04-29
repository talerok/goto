import SwiftUI

@main
struct GotoApp: App {
    @FocusedValue(\.appState) private var appState

    var body: some Scene {
        WindowGroup(for: URL.self) { $url in
            WindowRoot(initialURL: url)
        }
        .commands {
            appCommands
        }
        .defaultSize(width: 800, height: 600)

        Settings {
            SettingsView()
        }
    }

    @CommandsBuilder
    private var appCommands: some Commands {
        CommandGroup(replacing: .toolbar) {
            Button("Focus Address Bar") {
                appState?.addressBar.focusAndSelectAll()
            }
            .keyboardShortcut("l", modifiers: .command)

            Divider()

            Button("Back") {
                appState?.navigateBack()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(appState?.navigation.canGoBack != true)

            Button("Forward") {
                appState?.navigateForward()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(appState?.navigation.canGoForward != true)

            Button("Enclosing Folder") {
                appState?.navigateUp()
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(appState?.navigation.canGoUp != true)

            Divider()

            Button("Toggle Hidden Files") {
                appState?.directory.showHiddenFiles.toggle()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])

            Divider()

            Button("Find") {
                appState?.toggleSearch()
            }
            .keyboardShortcut("f", modifiers: .command)

            Divider()

            Button("New Folder") {
                appState?.createNewFolder()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("New File") {
                appState?.createNewFile()
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("x", modifiers: .command)

            Button("Copy") {
                if appState?.addressBar.isFocused == true || appState?.renamingItem != nil || appState?.isSearching == true {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                } else {
                    appState?.copySelectedItems()
                }
            }
            .keyboardShortcut("c", modifiers: .command)

            Button("Paste") {
                if appState?.addressBar.isFocused == true || appState?.renamingItem != nil || appState?.isSearching == true {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                } else {
                    appState?.pasteItems()
                }
            }
            .keyboardShortcut("v", modifiers: .command)

            Button("Select All") {
                if appState?.addressBar.isFocused == true || appState?.renamingItem != nil || appState?.isSearching == true {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                } else {
                    appState?.selectAll()
                }
            }
            .keyboardShortcut("a", modifiers: .command)

            Divider()

            Button("Copy Path") {
                guard let appState else { return }
                let path = appState.navigation.currentDirectory.path(percentEncoded: false)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }
    }
}

// MARK: - Focused Value

private struct FocusedAppStateKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var appState: AppState? {
        get { self[FocusedAppStateKey.self] }
        set { self[FocusedAppStateKey.self] = newValue }
    }
}

// MARK: - Per-Window Root

struct WindowRoot: View {
    @State private var appState: AppState

    init(initialURL: URL?) {
        _appState = State(initialValue: AppState(startingDirectory: initialURL))
    }

    var body: some View {
        ContentView()
            .environment(appState)
            .focusedValue(\.appState, appState)
            .navigationTitle(appState.navigation.currentDirectory.lastPathComponent)
    }
}
