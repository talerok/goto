import SwiftUI

struct FileListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var state = appState

        // Access renamingItem so SwiftUI tracks it — changes trigger updateNSView for rename state.
        let _ = appState.renamingItem

        ZStack {
            if appState.directory.isLoading && appState.directory.items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = appState.directory.error {
                errorView(error)
            } else {
                NativeFileTableView(
                    items: appState.directory.items,
                    selection: Binding(
                        get: { appState.selection },
                        set: { appState.selection = $0 }
                    ),
                    appState: appState,
                    onOpenInNewWindow: { url in
                        openWindow(value: url)
                    }
                )
            }
        }
        .alert("Move to Trash?", isPresented: $state.showTrashConfirmation) {
            Button("Move to Trash", role: .destructive) {
                appState.confirmTrash()
            }
            Button("Cancel", role: .cancel) {
                appState.pendingTrashItems = []
            }
        } message: {
            Text("Are you sure you want to move \(appState.pendingTrashItems.count) items to the Trash?")
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
