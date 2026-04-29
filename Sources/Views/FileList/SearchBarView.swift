import SwiftUI

/// In-folder search bar shown between the toolbar and the file list.
struct SearchBarView: View {
    @Environment(AppState.self) private var appState
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            TextField("Search in folder…", text: Binding(
                get: { appState.directory.searchText },
                set: { appState.directory.searchText = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused($isFocused)
            .onSubmit { /* keep search active, do nothing on Enter */ }
            .onKeyPress(.escape) {
                appState.dismissSearch()
                return .handled
            }

            if !appState.directory.searchText.isEmpty {
                Button {
                    appState.directory.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Text("\(appState.directory.items.count) items")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.bar)
        .onAppear {
            isFocused = true
        }
        .onChange(of: appState.searchWantsFocus) { _, wants in
            if wants {
                isFocused = true
                appState.searchWantsFocus = false
            }
        }
    }
}
