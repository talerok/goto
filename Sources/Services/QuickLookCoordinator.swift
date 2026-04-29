import AppKit
import Quartz

/// Bridges QLPreviewPanel with the SwiftUI app for Space-to-preview functionality.
@MainActor
final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookCoordinator()

    private(set) var previewURLs: [URL] = []

    /// Toggle Quick Look for the given URLs. If already showing, dismiss.
    func toggle(urls: [URL]) {
        guard let panel = QLPreviewPanel.shared() else { return }

        if panel.isVisible {
            panel.orderOut(nil)
            return
        }

        previewURLs = urls
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Refresh the preview panel with new URLs (e.g., when selection changes while panel is open).
    func update(urls: [URL]) {
        previewURLs = urls
        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.reloadData()
        }
    }

    // MARK: - QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { previewURLs.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        let urls = MainActor.assumeIsolated { previewURLs }
        guard urls.indices.contains(index) else { return nil }
        return urls[index] as NSURL
    }
}
