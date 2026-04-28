import SwiftUI

struct FileListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        ZStack {
            if appState.directory.isLoading && appState.directory.items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = appState.directory.error {
                errorView(error)
            } else if appState.directory.items.isEmpty {
                emptyView
            } else {
                fileTable
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

    private var fileTable: some View {
        Table(appState.directory.items, selection: Binding(
            get: { appState.selection },
            set: { appState.selection = $0 }
        )) {
            TableColumn("Name") { item in
                FileNameCell(
                    item: item,
                    isRenaming: appState.renamingItem?.id == item.id,
                    renameText: Binding(
                        get: { appState.renameText },
                        set: { appState.renameText = $0 }
                    ),
                    onCommitRename: { appState.commitRename() },
                    onCancelRename: { appState.cancelRename() }
                )
            }
            .width(min: 200, ideal: 350)

            TableColumn("Date Modified") { item in
                Text(item.formattedDate)
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .default))
            }
            .width(min: 120, ideal: 160)

            TableColumn("Size") { item in
                Text(item.formattedSize)
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 80)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            contextMenuContent(for: ids)
        } primaryAction: { ids in
            handlePrimaryAction(ids)
        }
        .tableColumnHeaders(.visible)
    }

    @ViewBuilder
    private func contextMenuContent(for ids: Set<String>) -> some View {
        let items = appState.directory.items.filter { ids.contains($0.id) }
        let single = items.count == 1 ? items.first : nil

        Button("Open") {
            handlePrimaryAction(ids)
        }

        if let item = single {
            Button("Open With…") {
                FileSystemService.openWith(item.url)
            }
        }

        if let item = single {
            Button("Rename") {
                appState.startRenaming(item)
            }
        }

        Divider()

        Button("Copy Path") {
            if let item = single {
                FileSystemService.copyPath(item.url)
            } else {
                let paths = items.map { $0.url.path(percentEncoded: false) }.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(paths, forType: .string)
            }
        }

        Divider()

        Button("Move to Trash", role: .destructive) {
            appState.selection = ids
            appState.trashSelectedItems()
        }

        if let item = single {
            Divider()
            Button("Get Info") {
                FileSystemService.showGetInfo(item.url)
            }
        }
    }

    private func handlePrimaryAction(_ ids: Set<String>) {
        let items = appState.directory.items.filter { ids.contains($0.id) }
        guard !items.isEmpty else { return }

        if items.count == 1, let item = items.first, item.isDirectory {
            Task { await appState.navigate(to: item.url) }
        } else {
            for item in items {
                if item.isDirectory {
                    Task { await appState.navigate(to: item.url) }
                } else {
                    FileSystemService.open(item.url)
                }
            }
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

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Empty Folder")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - File Name Cell

private struct FileNameCell: View {
    let item: FileItem
    let isRenaming: Bool
    @Binding var renameText: String
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void

    @State private var icon: NSImage?
    @FocusState private var isEditing: Bool

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                } else {
                    Image(systemName: item.isDirectory ? "folder.fill" : "doc")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(contentMode: .fit)
            .frame(width: 18, height: 18)

            if isRenaming {
                TextField("", text: $renameText)
                    .textFieldStyle(.plain)
                    .focused($isEditing)
                    .onSubmit {
                        onCommitRename()
                    }
                    .onExitCommand {
                        onCancelRename()
                    }
            } else {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .task(id: item.id) {
            icon = await IconProvider.icon(for: item)
        }
        .opacity(item.isHidden ? 0.5 : 1.0)
        .onChange(of: isRenaming) { _, newValue in
            if newValue {
                isEditing = true
            }
        }
    }
}
