import SwiftUI

/// File association settings — extension → application mapping.
struct SettingsView: View {
    @State private var associations: [(key: String, bundleID: String)] = []
    @State private var showingAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("File Associations")
                .font(.headline)
                .padding(.bottom, 8)

            Text("Set default applications for file types. These override the system default when opening files.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)

            List {
                ForEach(associations, id: \.key) { item in
                    HStack(spacing: 8) {
                        Text(item.key == "folder" ? "Folder" : ".\(item.key)")
                            .font(.body.monospaced())
                            .frame(width: 80, alignment: .leading)

                        if let appURL = FileAssociationService.appURL(forBundleID: item.bundleID) {
                            Image(nsImage: appIcon(at: appURL))
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(FileAssociationService.appDisplayName(at: appURL))
                        } else {
                            Image(systemName: "questionmark.app")
                                .frame(width: 16, height: 16)
                            Text(item.bundleID)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            removeAssociation(key: item.key)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.bordered)
            .frame(minHeight: 150)

            HStack {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                Spacer()
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 480, height: 380)
        .onAppear { loadAssociations() }
        .sheet(isPresented: $showingAddSheet) {
            AddAssociationSheet(existingKeys: Set(associations.map(\.key))) { key, bundleID in
                FileAssociationService.setDefaultApp(bundleID: bundleID, forKey: key)
                loadAssociations()
            }
        }
    }

    private func loadAssociations() {
        associations = FileAssociationService.allAssociations()
            .map { (key: $0.key, bundleID: $0.value) }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    private func removeAssociation(key: String) {
        FileAssociationService.removeAssociation(forKey: key)
        loadAssociations()
    }

    private func appIcon(at url: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}

// MARK: - Add Association Sheet

struct AddAssociationSheet: View {
    let existingKeys: Set<String>
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var extensionText = ""
    @State private var isFolder = false
    @State private var selectedAppURL: URL?
    @State private var selectedAppName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add File Association")
                .font(.headline)

            Toggle("Folder", isOn: $isFolder)

            if !isFolder {
                HStack {
                    Text("Extension:")
                    TextField("e.g. txt, swift, md", text: $extensionText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
            }

            HStack {
                Text("Application:")
                if let appURL = selectedAppURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path(percentEncoded: false)))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(selectedAppName)
                } else {
                    Text("None")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose…") { pickApplication() }
            }

            if let error = validationError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private var normalizedKey: String {
        if isFolder { return "folder" }
        return extensionText
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private var canSave: Bool {
        selectedAppURL != nil && !normalizedKey.isEmpty && validationError == nil
    }

    private var validationError: String? {
        let key = normalizedKey
        guard !key.isEmpty else { return nil }
        if existingKeys.contains(key) {
            return "Association for \(isFolder ? "Folder" : ".\(key)") already exists."
        }
        return nil
    }

    private func pickApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedAppURL = url
        selectedAppName = FileAssociationService.appDisplayName(at: url)
    }

    private func save() {
        guard let appURL = selectedAppURL,
              let bundle = Bundle(url: appURL),
              let bundleID = bundle.bundleIdentifier else { return }

        let key = normalizedKey
        guard !key.isEmpty, !existingKeys.contains(key) else { return }
        onSave(key, bundleID)
        dismiss()
    }
}
