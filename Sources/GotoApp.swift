import SwiftUI

@main
struct GotoApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        Window("Goto", id: "main") {
            ContentView()
                .environment(appState)
        }
        .commands {
            appCommands
        }
        .defaultSize(width: 800, height: 600)
    }

    @CommandsBuilder
    private var appCommands: some Commands {
        CommandGroup(replacing: .toolbar) {
            Button("Focus Address Bar") {
                appState.addressBar.focusAndSelectAll()
            }
            .keyboardShortcut("l", modifiers: .command)

            Divider()

            Button("Back") {
                appState.navigateBack()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!appState.navigation.canGoBack)

            Button("Forward") {
                appState.navigateForward()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(!appState.navigation.canGoForward)

            Button("Enclosing Folder") {
                appState.navigateUp()
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(!appState.navigation.canGoUp)

            Divider()

            Button("Toggle Hidden Files") {
                appState.directory.showHiddenFiles.toggle()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Copy Path") {
                let path = appState.navigation.currentDirectory.path(percentEncoded: false)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }
    }
}
