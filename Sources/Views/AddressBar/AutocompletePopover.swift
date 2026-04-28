import SwiftUI

/// Dropdown list of directory suggestions shown below the address bar during editing.
struct AutocompletePopover: View {
    let suggestions: [URL]
    let selectedIndex: Int?
    let onSelect: (URL) -> Void

    private let maxVisible = 10

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, url in
                        suggestionRow(url, index: index)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: CGFloat(min(suggestions.count, maxVisible)) * 32 + 8)
            .onChange(of: selectedIndex) { _, newValue in
                if let idx = newValue {
                    proxy.scrollTo(idx, anchor: .center)
                }
            }
        }
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        )
    }

    private func suggestionRow(_ url: URL, index: Int) -> some View {
        Button {
            onSelect(url)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 14))
                    .frame(width: 18)
                Text(url.lastPathComponent)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(url.deletingLastPathComponent().path(percentEncoded: false))
                    .lineLimit(1)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(index == selectedIndex ? Color.accentColor.opacity(0.15) : .clear)
                    .padding(.horizontal, 4)
            )
        }
        .buttonStyle(.plain)
        .id(index)
    }
}
