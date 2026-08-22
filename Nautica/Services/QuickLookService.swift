import AppKit
import Quartz

/// Space-bar Quick Look preview (Prompt 9). Owns the shared `QLPreviewPanel`'s
/// data source and delegate. The file views hand it the whole current listing
/// plus the index of the selected item, so the panel's arrow keys walk the
/// folder; Esc or Space closes the panel natively once it is key.
final class QuickLookService: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookService()

    private(set) var previewURLs: [URL] = []
    var currentIndex: Int = 0

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && (QLPreviewPanel.shared()?.isVisible ?? false)
    }

    /// Shows the panel (or retargets it while open) at `urls[selectedIndex]`.
    func showPreview(for urls: [URL], selectedIndex: Int) {
        guard !urls.isEmpty else { return }
        previewURLs = urls
        currentIndex = max(0, min(selectedIndex, urls.count - 1))
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.currentPreviewItemIndex = currentIndex
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func hidePreview() {
        guard QLPreviewPanel.sharedPreviewPanelExists() else { return }
        QLPreviewPanel.shared()?.orderOut(nil)
    }

    func togglePreview(for urls: [URL], selectedIndex: Int) {
        if isVisible {
            hidePreview()
        } else {
            showPreview(for: urls, selectedIndex: selectedIndex)
        }
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURLs[index] as NSURL
    }
}
