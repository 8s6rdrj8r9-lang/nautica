import AppKit
import SwiftUI

/// Focused directory of the key browser window, read by the app-level
/// commands (Cmd+T opens a new tab at this location).
private struct FocusedBrowserURLKey: FocusedValueKey {
    typealias Value = URL
}

/// File-operation entry points of the key browser window, read by the Edit
/// menu commands (Prompt 10).
struct BrowserActions {
    var copySelection: () -> Void
    /// Paste (copy) the pasteboard items into the current folder.
    var paste: () -> Void
    /// Paste by moving (Cmd+Opt+V).
    var moveHere: () -> Void
    var trashSelection: () -> Void
    var renameSelection: () -> Void
    // Navigation (Go menu, Prompt 16).
    var goBack: () -> Void
    var goForward: () -> Void
    var goToEnclosingFolder: () -> Void
    var navigateTo: (URL) -> Void
    /// "Go to Folder…" prompt.
    var promptGoToFolder: () -> Void
    // View menu (Prompt 16).
    var setViewMode: (ViewMode) -> Void
    var toggleHiddenFiles: () -> Void
    /// Toggles the right-hand tree panel.
    var toggleTreePanel: () -> Void
}

private struct FocusedBrowserActionsKey: FocusedValueKey {
    typealias Value = BrowserActions
}

extension FocusedValues {
    var browserURL: URL? {
        get { self[FocusedBrowserURLKey.self] }
        set { self[FocusedBrowserURLKey.self] = newValue }
    }

    var browserActions: BrowserActions? {
        get { self[FocusedBrowserActionsKey.self] }
        set { self[FocusedBrowserActionsKey.self] = newValue }
    }
}

/// Heap box for `NSUndoManager.registerUndo(withTarget:handler:)`, which
/// requires an `AnyObject` target.
private final class UndoBox {
    let work: () -> Void
    init(_ work: @escaping () -> Void) { self.work = work }
}

/// Main window content: sidebar + file view, driven by a per-tab state
/// (`TabState`) that owns navigation history, directory listing, selection,
/// and view mode (Prompt 8).
struct BrowserView: View {
    @State private var tab = TabState(url: Constants.defaultWindowURL())
    @State private var sidebarModel = SidebarModel()
    @AppStorage(Constants.defaultIconSizeKey) private var iconSize: Double = 64
    /// Session-level default for the hidden-files toggle.
    @State private var showHiddenFiles = UserDefaults.standard.bool(forKey: Constants.showHiddenFilesKey)
    @State private var toolbar = BrowserToolbar()
    /// Rename sheet state (Prompt 10).
    @State private var renameTarget: FileItem?
    @State private var renameText = ""
    /// Long-running copy/move progress; non-nil presents the sheet.
    @State private var operationName = ""
    @State private var operationProgress: Progress?
    @State private var isOperationRunning = false
    /// Persistent banner while Full Disk Access is missing (Prompt 15).
    @State private var showPermissionBanner = false
    /// "Go to Folder…" sheet state (Prompt 16).
    @State private var showGoToFolderSheet = false
    @State private var goToFolderText = ""
    /// Right-hand directory tree panel.
    @State private var showTreePanel = true
    @Environment(\.undoManager) private var undoManager
    @Environment(\.modelContext) private var modelContext
    /// Per-folder view state persistence (Prompt 12); created in onAppear
    /// once the model context is available.
    @State private var viewStateService: ViewStateService?

    var body: some View {
        VStack(spacing: 0) {
            if showPermissionBanner {
                permissionBanner
            }
            NavigationSplitView {
                SidebarView(model: sidebarModel) { url in
                    navigate(to: url)
                } onFavoriteAdded: { _ in
                    // Persistence handled by SidebarModel; hook for later prompts.
                }
            } detail: {
                VStack(spacing: 0) {
                    if let error = tab.directoryContents.error {
                        ContentUnavailableView {
                            Label("Unable to Open Folder", systemImage: "exclamationmark.folder")
                        } description: {
                            Text(error.localizedDescription)
                        } actions: {
                            Button("Retry") { tab.directoryContents.reload() }
                        }
                    } else {
                        FileViewCoordinator(
                            directoryContents: tab.directoryContents,
                            selectionModel: tab.selectionModel,
                            viewMode: tab.viewMode,
                            onQuickLook: quickLook,
                            iconSize: iconSize,
                            onNavigate: navigate(to:),
                            onRenameRequest: renameSelection,
                            onCopySelection: copySelectionToPasteboard,
                            onTrashSelection: trashSelection
                        )
                    }
                }
            }
        }
        .inspector(isPresented: $showTreePanel) {
            TreePanelView(model: sidebarModel, onNavigate: navigate(to:))
                .inspectorColumnWidth(min: 200, ideal: 260, max: 400)
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(WindowAccessor(toolbar: toolbar.toolbar, onWindow: configureWindow))
        .focusedSceneValue(\.browserURL, tab.navigationHistory.currentURL)
        .focusedSceneValue(\.browserActions, BrowserActions(
            copySelection: copySelectionToPasteboard,
            paste: { pasteFromPasteboard(move: false) },
            moveHere: { pasteFromPasteboard(move: true) },
            trashSelection: trashSelection,
            renameSelection: renameSelection,
            goBack: goBack,
            goForward: goForward,
            goToEnclosingFolder: {
                navigate(to: tab.navigationHistory.currentURL.deletingLastPathComponent())
            },
            navigateTo: navigate(to:),
            promptGoToFolder: { showGoToFolderSheet = true },
            setViewMode: setViewMode,
            toggleHiddenFiles: toggleHiddenFiles,
            toggleTreePanel: { showTreePanel.toggle() }
        ))
        .sheet(isPresented: showsOperationSheet) {
            if let operationProgress {
                ProgressPanel(
                    progress: operationProgress,
                    operationName: operationName,
                    onCancel: cancelOperation
                )
                .interactiveDismissDisabled()
            }
        }
        .sheet(item: $renameTarget) { item in
            renameSheet(for: item)
        }
        .sheet(isPresented: $showGoToFolderSheet) {
            goToFolderSheet
        }
        .onAppear {
            if viewStateService == nil {
                viewStateService = ViewStateService(context: modelContext)
                tab.directoryContents.onSortChanged = persistViewState
            }
            wireToolbar()
            restoreIfPending()
            applyViewState(for: tab.navigationHistory.currentURL)
            showPermissionBanner = !FullDiskAccess.isGranted
        }
        .onChange(of: iconSize) { syncToolbar() }
        .task { tab.directoryContents.reload() }
    }

    /// Single navigation entry point: sidebar, path bar, and double-click on a
    /// folder all route here. Pushes history, then shows the new location.
    private func navigate(to url: URL) {
        tab.navigationHistory.navigate(to: url)
        show(url)
    }

    /// Shows a location without touching the history stacks. Used by `navigate`
    /// (history already pushed) and by back/forward (stacks already updated).
    private func show(_ url: URL) {
        tab.directoryContents.url = url
        applyViewState(for: url)
        tab.directoryContents.showHiddenFiles = showHiddenFiles
        tab.directoryContents.reload()
        sidebarModel.recordVisit(url)
        tab.selectionModel.deselectAll()
        syncToolbar()
    }

    /// Restores the persisted per-folder view state (Prompt 12), if any.
    private func applyViewState(for url: URL) {
        guard let state = viewStateService?.state(for: url.path) else { return }
        tab.viewMode = ViewMode(rawValue: state.viewMode) ?? .icon
        showHiddenFiles = state.showHiddenFiles
        tab.directoryContents.sortKey = SortKey(rawValue: state.sortKey) ?? .name
        tab.directoryContents.sortAscending = state.sortAscending
    }

    /// Mirrors the current view settings into the folder's state and saves
    /// after a 500 ms quiet period (Prompt 12).
    private func persistViewState() {
        guard let state = viewStateService?.current else { return }
        state.viewMode = tab.viewMode.rawValue
        state.sortKey = tab.directoryContents.sortKey.rawValue
        state.sortAscending = tab.directoryContents.sortAscending
        state.showHiddenFiles = showHiddenFiles
        viewStateService?.scheduleSave()
    }

    private func goBack() {
        guard let url = tab.navigationHistory.goBack() else { return }
        show(url)
    }

    private func goForward() {
        guard let url = tab.navigationHistory.goForward() else { return }
        show(url)
    }

    private func wireToolbar() {
        toolbar.onBack = goBack
        toolbar.onForward = goForward
        toolbar.onNavigate = navigate(to:)
        toolbar.onAddFavorite = { url in sidebarModel.addFavorite(url: url) }
        toolbar.onViewModeChanged = { [weak toolbar] mode in
            setViewMode(mode)
            toolbar?.refresh()
        }
        toolbar.onIconSizeChanged = { [weak toolbar] size in
            _iconSize.wrappedValue = size
            toolbar?.iconSize = size
            persistViewState()
        }
        toolbar.onToggleHiddenFiles = { [weak toolbar] in
            toggleHiddenFiles()
            toolbar?.refresh()
        }
        syncToolbar()
    }

    /// Switches icon/list view and persists the choice (Prompts 12, 16).
    private func setViewMode(_ mode: ViewMode) {
        tab.viewMode = mode
        toolbar.viewMode = mode
        toolbar.refresh()
        persistViewState()
    }

    /// Flips hidden-file visibility and reloads (Prompts 7, 16).
    private func toggleHiddenFiles() {
        showHiddenFiles.toggle()
        tab.directoryContents.showHiddenFiles = showHiddenFiles
        tab.directoryContents.reload()
        toolbar.showsHiddenFiles = showHiddenFiles
        toolbar.refresh()
        persistViewState()
    }

    /// Mirrors SwiftUI state into the toolbar and revalidates its items.
    private func syncToolbar() {
        toolbar.canGoBack = tab.navigationHistory.canGoBack
        toolbar.canGoForward = tab.navigationHistory.canGoForward
        toolbar.currentURL = tab.navigationHistory.currentURL
        toolbar.viewMode = tab.viewMode
        toolbar.iconSize = iconSize
        toolbar.showsHiddenFiles = showHiddenFiles
        toolbar.refresh()
    }

    /// Space: Quick Look the selected item (Prompt 9). The panel receives the
    /// whole listing so its arrow keys walk the folder; Esc or Space closes it.
    private func quickLook() {
        let items = tab.directoryContents.items
        let selection = tab.selectionModel
        let anchor = selection.lastClickedID ?? selection.selectedIDs.first
        guard let anchor, let index = items.firstIndex(where: { $0.id == anchor }) else {
            QuickLookService.shared.hidePreview()
            return
        }
        QuickLookService.shared.togglePreview(for: items.map(\.url), selectedIndex: index)
    }

    // MARK: - File operations (Prompt 10)

    private var selectedItems: [FileItem] {
        tab.directoryContents.items.filter { tab.selectionModel.selectedIDs.contains($0.id) }
    }

    /// Cmd+C: put the selected file URLs on the general pasteboard.
    private func copySelectionToPasteboard() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
    }

    /// Cmd+V copies into the current folder; Cmd+Opt+V moves.
    private func pasteFromPasteboard(move: Bool) {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        guard let urls = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self], options: options
        ) as? [URL], !urls.isEmpty else { return }
        let destination = tab.navigationHistory.currentURL
        let sources = urls
        runFileOperation(move ? "Moving Files" : "Copying Files") { progress in
            move
                ? await FileOperationService.shared.moveItems(sources, to: destination, progress: progress)
                : await FileOperationService.shared.copyItems(sources, to: destination, progress: progress)
        } onCompletion: { result in
            // Undo of a move: put everything back where it came from.
            if move {
                registerRestoreUndo(
                    name: "Move", transfers: result.transfers
                )
            }
        }
    }

    /// Cmd+Delete: move the selection to the Trash (undoable via Cmd+Z).
    private func trashSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        if UserDefaults.standard.bool(forKey: Constants.confirmTrashKey) {
            let alert = NSAlert()
            alert.messageText = urls.count == 1
                ? "Move “\(urls[0].lastPathComponent)” to the Trash?"
                : "Move \(urls.count) items to the Trash?"
            alert.addButton(withTitle: "Move to Trash")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        Task {
            let result = await FileOperationService.shared.trashItems(urls)
            tab.directoryContents.reload()
            tab.selectionModel.deselectAll()
            registerRestoreUndo(name: "Move to Trash", transfers: result.transfers)
            if let (_, error) = result.failed.first { showError("Move to Trash Failed", error: error) }
        }
    }

    /// Return/Enter with a single selection: present the rename sheet.
    private func renameSelection() {
        let selected = selectedItems
        guard selected.count == 1, let item = selected.first else { return }
        renameText = item.name
        renameTarget = item
    }

    private func renameSheet(for item: FileItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename “\(item.name)”")
                .font(.headline)
            TextField("Name", text: $renameText)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { renameTarget = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { commitRename(of: item) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func commitRename(of item: FileItem) {
        let newName = renameText
        renameTarget = nil
        Task {
            do {
                _ = try await FileOperationService.shared.renameItem(at: item.url, to: newName)
            } catch {
                await MainActor.run { showError("Rename Failed", error: error) }
            }
            tab.directoryContents.reload()
        }
    }

    /// "Go to Folder…" sheet (Prompt 16, Cmd+Shift+G).
    private var goToFolderSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Go to Folder")
                .font(.headline)
            TextField("Path (e.g. ~/Documents)", text: $goToFolderText)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showGoToFolderSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Go") {
                    let path = (goToFolderText as NSString).expandingTildeInPath
                    let url = URL(fileURLWithPath: path)
                    showGoToFolderSheet = false
                    goToFolderText = ""
                    navigate(to: url)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(goToFolderText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    /// User-facing alert for failed file operations (Prompt 16).
    private func showError(_ title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private var showsOperationSheet: Binding<Bool> {
        Binding(
            get: { operationProgress != nil },
            set: { if !$0 { cancelOperation() } }
        )
    }

    /// Runs a copy/move off the main thread, presenting the progress sheet
    /// only if the operation is still running after one second.
    private func runFileOperation(
        _ name: String,
        operation: @escaping (Progress) async -> FileOperationResult,
        onCompletion: ((FileOperationResult) -> Void)? = nil
    ) {
        guard !isOperationRunning else { return }
        isOperationRunning = true
        let progress = Progress(totalUnitCount: 1)
        let showDelay = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled, !progress.isFinished, !progress.isCancelled {
                operationName = name
                operationProgress = progress
            }
        }
        Task {
            let result = await operation(progress)
            await MainActor.run {
                showDelay.cancel()
                operationProgress = nil
                isOperationRunning = false
                tab.directoryContents.reload()
                onCompletion?(result)
                if let (url, error) = result.failed.first(where: { !($0.1 is CancellationError) }) {
                    showError(
                        "\(name) failed for “\(url.lastPathComponent)”",
                        error: error
                    )
                }
            }
        }
    }

    private func cancelOperation() {
        operationProgress?.cancel()
    }

    /// Restore successful transfers to their exact original paths, including names.
    private func registerRestoreUndo(name: String, transfers: [FileOperationResult.Transfer]) {
        guard let undoManager, !transfers.isEmpty else { return }
        undoManager.registerUndo(withTarget: UndoBox {
            Task {
                let result = await FileOperationService.shared.restoreItems(transfers)
                tab.directoryContents.reload()
                if let (_, error) = result.failed.first {
                    showError("Undo Failed", error: error)
                }
            }
        }) { box in
            box.work()
        }
        undoManager.setActionName(name)
    }

    /// Consumes a pending URL queued for this window (restored tab on launch,
    /// or Cmd+T "new tab here"), if any.
    private func restoreIfPending() {
        guard let url = TabRestoreQueue.shared.pop() else { return }
        navigate(to: url)
    }

    /// Enables native window tabbing and registers the window so its current
    /// directory can be saved on quit.
    private func configureWindow(_ window: NSWindow) {
        window.tabbingMode = .preferred
        WindowTabRegistry.shared.register(window) { [tab] in
            tab.navigationHistory.currentURL
        }
    }

    /// Persistent banner shown while Full Disk Access is missing (Prompt 15).
    private var permissionBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
            Text("Nautica doesn't have Full Disk Access, so some folders may be unavailable.")
                .font(.callout)
            Spacer()
            Button("Open System Settings") {
                FullDiskAccess.openSystemSettings()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.15))
    }
}

/// Hands the browser's NSToolbar to the hosting NSWindow once it exists, and
/// gives the window a one-time (idempotent) configuration pass.
private struct WindowAccessor: NSViewRepresentable {
    let toolbar: NSToolbar
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Fallback for the case where makeNSView ran before the view joined
        // a window.
        DispatchQueue.main.async { configure(nsView) }
    }

    /// Assigns the toolbar exactly once, always outside the current layout
    /// pass. Assigning `window.toolbar` twice — even the same instance —
    /// makes SwiftUI's BarAppearanceBridge over-remove its `displayMode`
    /// KVO observer and crash with NSRangeException.
    private func configure(_ view: NSView) {
        guard let window = view.window else { return }
        if window.toolbar == nil {
            window.toolbar = toolbar
        }
        onWindow(window)
    }
}

#Preview {
    BrowserView()
}
