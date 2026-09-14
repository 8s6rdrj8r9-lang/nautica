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
    var batchRenameSelection: () -> Void
    var newFolder: () -> Void
    var getInfo: () -> Void
    var quickLook: () -> Void
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
    /// Sets multi-pane split layout (F-004).
    var setSplitLayout: (SplitLayout) -> Void
    /// Toggles between single pane and dual pane.
    var toggleDualPane: () -> Void
    /// Cycles to the next pane (Option+Tab).
    var cycleNextPane: () -> Void
    /// Toggles the bottom path bar (Option+Command+P).
    var togglePathBar: () -> Void
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
    @AppStorage(Constants.splitLayoutKey) private var splitLayoutRaw: Int = SplitLayout.single.rawValue
    private var splitLayout: SplitLayout {
        get { SplitLayout(rawValue: splitLayoutRaw) ?? .single }
        nonmutating set { _splitLayoutRaw.wrappedValue = newValue.rawValue }
    }
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var activePaneIndex: Int = 0
    @State private var panes: [TabState] = [
        TabState(url: FileManager.default.homeURL),
        TabState(url: FileManager.default.homeURL.appendingPathComponent("Documents")),
        TabState(url: FileManager.default.homeURL.appendingPathComponent("Downloads")),
        TabState(url: FileManager.default.homeURL.appendingPathComponent("Desktop"))
    ]

    @State private var sidebarModel = SidebarModel()
    @AppStorage(Constants.defaultIconSizeKey) private var iconSize: Double = 64
    /// Session-level default for the hidden-files toggle.
    @State private var showHiddenFiles = UserDefaults.standard.bool(forKey: Constants.showHiddenFilesKey)
    @State private var toolbar = BrowserToolbar()
    /// Rename sheet state (Prompt 10).
    @State private var renameTarget: FileItem?
    @State private var renameText = ""
    /// Batch rename sheet state (Prompt 17 / F-012).
    @State private var showBatchRenameSheet = false
    @State private var batchRenameTargets: [FileItem] = []
    /// Long-running copy/move progress; non-nil presents the sheet.
    @State private var operationName = ""
    @State private var operationProgress: Progress?
    @State private var isOperationRunning = false
    /// Persistent banner while Full Disk Access is missing (Prompt 15).
    @State private var showPermissionBanner = false
    @AppStorage("dismissedFullDiskBanner") private var dismissedFullDiskBanner = false
    /// "Go to Folder…" sheet state (Prompt 16).
    @State private var showGoToFolderSheet = false
    @State private var goToFolderText = ""
    @AppStorage("showPathBar") private var showPathBar = true
    /// Right-hand directory tree panel.
    @State private var showTreePanel = false
    @Environment(\.undoManager) private var undoManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    /// Per-folder view state persistence (Prompt 12); created in onAppear
    /// once the model context is available.
    @State private var viewStateService: ViewStateService?

    private var activeTab: TabState {
        if panes.indices.contains(activePaneIndex) {
            return panes[activePaneIndex]
        }
        return panes.first ?? TabState(url: Constants.defaultWindowURL())
    }

    private var activePanes: [TabState] {
        Array(panes.prefix(splitLayout.paneCount))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(model: sidebarModel, selectedURL: activeTab.navigationHistory.currentURL) { url in
                navigate(to: url)
            } onFavoriteAdded: { _ in
                // Persistence handled by SidebarModel; hook for later prompts.
            }
            .frame(minWidth: 170, idealWidth: 190, maxWidth: 260)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 260)
        } detail: {
            VStack(spacing: 0) {
                if showPermissionBanner && !dismissedFullDiskBanner {
                    permissionBanner
                }
                splitLayoutView

                if showPathBar {
                    Divider()
                    HStack(spacing: 8) {
                        PathBarView(currentURL: activeTab.navigationHistory.currentURL) { url in
                            navigate(to: url)
                        } onAddFavorite: { url in
                            sidebarModel.addFavorite(url: url)
                        }
                        Spacer()
                        statusBarInfo
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.windowBackgroundColor))
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $showTreePanel) {
            TreePanelView(model: sidebarModel, onNavigate: navigate(to:))
                .inspectorColumnWidth(min: 200, ideal: 260, max: 400)
        }
        .frame(minWidth: 720, minHeight: 450)
        .background(WindowAccessor(toolbar: toolbar.toolbar, onWindow: configureWindow))
        .focusedSceneValue(\.browserURL, activeTab.navigationHistory.currentURL)
        .focusedSceneValue(\.browserActions, BrowserActions(
            copySelection: copySelectionToPasteboard,
            paste: { pasteFromPasteboard(move: false) },
            moveHere: { pasteFromPasteboard(move: true) },
            trashSelection: trashSelection,
            renameSelection: renameSelection,
            batchRenameSelection: batchRenameSelection,
            newFolder: {
                let destination = activeTab.navigationHistory.currentURL.appendingPathComponent("untitled folder")
                try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                for pane in activePanes { pane.directoryContents.reload() }
            },
            getInfo: {
                if let first = selectedItems.first {
                    FileContextMenu.showInfo(for: first)
                }
            },
            quickLook: quickLook,
            goBack: goBack,
            goForward: goForward,
            goToEnclosingFolder: {
                navigate(to: activeTab.navigationHistory.currentURL.deletingLastPathComponent())
            },
            navigateTo: navigate(to:),
            promptGoToFolder: { showGoToFolderSheet = true },
            setViewMode: setViewMode,
            toggleHiddenFiles: toggleHiddenFiles,
            setSplitLayout: setSplitLayout,
            toggleDualPane: toggleDualPane,
            cycleNextPane: cycleNextPane,
            togglePathBar: { showPathBar.toggle() },
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
        .sheet(isPresented: $showBatchRenameSheet) {
            BatchRenameSheet(items: batchRenameTargets) { renames in
                applyBatchRename(renames)
            }
        }
        .sheet(isPresented: $showGoToFolderSheet) {
            goToFolderSheet
        }
        .onAppear {
            if viewStateService == nil {
                viewStateService = ViewStateService(context: modelContext)
                activeTab.directoryContents.onSortChanged = persistViewState
            }
            wireToolbar()
            restoreIfPending()
            applyViewState(for: activeTab.navigationHistory.currentURL)
            showPermissionBanner = !FullDiskAccess.isGranted
        }
        .onChange(of: iconSize) { syncToolbar() }
        .task {
            for pane in activePanes {
                pane.directoryContents.reload()
            }
        }
    }

    @ViewBuilder
    private var splitLayoutView: some View {
        switch splitLayout {
        case .single:
            if let first = panes.first {
                paneView(for: first, index: 0)
            }

        case .horizontal2:
            if panes.count >= 2 {
                HSplitView {
                    paneView(for: panes[0], index: 0)
                    paneView(for: panes[1], index: 1)
                }
            } else if let first = panes.first {
                paneView(for: first, index: 0)
            }

        case .vertical2:
            if panes.count >= 2 {
                VSplitView {
                    paneView(for: panes[0], index: 0)
                    paneView(for: panes[1], index: 1)
                }
            } else if let first = panes.first {
                paneView(for: first, index: 0)
            }

        case .quad4:
            if panes.count >= 4 {
                VSplitView {
                    HSplitView {
                        paneView(for: panes[0], index: 0)
                        paneView(for: panes[1], index: 1)
                    }
                    HSplitView {
                        paneView(for: panes[2], index: 2)
                        paneView(for: panes[3], index: 3)
                    }
                }
            } else if let first = panes.first {
                paneView(for: first, index: 0)
            }

        case .horizontal4:
            if panes.count >= 4 {
                HSplitView {
                    paneView(for: panes[0], index: 0)
                    paneView(for: panes[1], index: 1)
                    paneView(for: panes[2], index: 2)
                    paneView(for: panes[3], index: 3)
                }
            } else if let first = panes.first {
                paneView(for: first, index: 0)
            }

        case .vertical4:
            if panes.count >= 4 {
                VSplitView {
                    paneView(for: panes[0], index: 0)
                    paneView(for: panes[1], index: 1)
                    paneView(for: panes[2], index: 2)
                    paneView(for: panes[3], index: 3)
                }
            } else if let first = panes.first {
                paneView(for: first, index: 0)
            }
        }
    }

    @ViewBuilder
    private func paneView(for currentTab: TabState, index: Int) -> some View {
        let isFocused = activePaneIndex == index
        VStack(spacing: 0) {
            if splitLayout != .single {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 13))
                        .foregroundStyle(isFocused ? Color.accentColor : .secondary)
                    Text(currentTab.navigationHistory.currentURL.lastPathComponent.isEmpty
                         ? "/"
                         : currentTab.navigationHistory.currentURL.lastPathComponent)
                        .font(.system(size: 12, weight: isFocused ? .semibold : .regular))
                        .foregroundStyle(isFocused ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if isFocused {
                        Text("Active")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.accentColor.opacity(0.14))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .contentShape(Rectangle())
                .onTapGesture {
                    activePaneIndex = index
                    syncToolbar()
                }
                Divider()
            }

            if let error = currentTab.directoryContents.error {
                ContentUnavailableView {
                    Label("Unable to Open Folder", systemImage: "exclamationmark.folder")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Retry") { currentTab.directoryContents.reload() }
                }
            } else {
                FileViewCoordinator(
                    directoryContents: currentTab.directoryContents,
                    selectionModel: currentTab.selectionModel,
                    viewMode: currentTab.viewMode,
                    onQuickLook: { quickLook(for: currentTab) },
                    iconSize: iconSize,
                    onNavigate: { url in navigate(to: url, in: currentTab) },
                    onRenameRequest: renameSelection,
                    onCopySelection: copySelectionToPasteboard,
                    onTrashSelection: trashSelection
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(splitLayout != .single && isFocused ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
                )
            }
        }
        .frame(minWidth: 160, minHeight: 120)
        .contentShape(Rectangle())
        .onTapGesture {
            activePaneIndex = index
            syncToolbar()
        }
        .onChange(of: currentTab.selectionModel.selectedIDs) {
            if !currentTab.selectionModel.selectedIDs.isEmpty && activePaneIndex != index {
                activePaneIndex = index
                syncToolbar()
            }
        }
    }

    /// Single navigation entry point: sidebar, path bar, and double-click on a
    /// folder all route here. Pushes history, then shows the new location.
    private func navigate(to url: URL) {
        navigate(to: url, in: activeTab)
    }

    private func navigate(to url: URL, in targetTab: TabState) {
        targetTab.navigationHistory.navigate(to: url)
        show(url, in: targetTab)
    }

    /// Shows a location without touching the history stacks. Used by `navigate`
    /// (history already pushed) and by back/forward (stacks already updated).
    private func show(_ url: URL, in targetTab: TabState) {
        targetTab.directoryContents.url = url
        if targetTab === activeTab {
            applyViewState(for: url)
        }
        targetTab.directoryContents.showHiddenFiles = showHiddenFiles
        targetTab.directoryContents.reload()
        sidebarModel.recordVisit(url)
        targetTab.selectionModel.deselectAll()
        if targetTab === activeTab {
            syncToolbar()
        }
    }

    /// Restores the persisted per-folder view state (Prompt 12), if any.
    private func applyViewState(for url: URL) {
        guard let state = viewStateService?.state(for: url.path) else { return }
        activeTab.viewMode = ViewMode(rawValue: state.viewMode) ?? .icon
        showHiddenFiles = state.showHiddenFiles
        activeTab.directoryContents.sortKey = SortKey(rawValue: state.sortKey) ?? .name
        activeTab.directoryContents.sortAscending = state.sortAscending
    }

    /// Mirrors the current view settings into the folder's state and saves
    /// after a 500 ms quiet period (Prompt 12).
    private func persistViewState() {
        guard let state = viewStateService?.current else { return }
        state.viewMode = activeTab.viewMode.rawValue
        state.sortKey = activeTab.directoryContents.sortKey.rawValue
        state.sortAscending = activeTab.directoryContents.sortAscending
        state.showHiddenFiles = showHiddenFiles
        viewStateService?.scheduleSave()
    }

    private func goBack() {
        guard let url = activeTab.navigationHistory.goBack() else { return }
        show(url, in: activeTab)
    }

    private func goForward() {
        guard let url = activeTab.navigationHistory.goForward() else { return }
        show(url, in: activeTab)
    }

    private func wireToolbar() {
        toolbar.onBack = goBack
        toolbar.onForward = goForward
        toolbar.onNavigate = { url in navigate(to: url) }
        toolbar.onAddFavorite = { url in sidebarModel.addFavorite(url: url) }
        toolbar.onSplitLayoutChanged = { [weak toolbar] layout in
            setSplitLayout(layout)
            toolbar?.refresh()
        }
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
        toolbar.onSortChanged = { key, ascending in
            activeTab.directoryContents.sort(by: key, ascending: ascending)
            persistViewState()
        }
        toolbar.onShare = {
            let urls = selectedItems.map(\.url)
            guard !urls.isEmpty else { return }
            let picker = NSSharingServicePicker(items: urls)
            if let window = NSApp.keyWindow, let contentView = window.contentView {
                picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
            }
        }
        toolbar.onNewFolder = {
            let destination = activeTab.navigationHistory.currentURL.appendingPathComponent("untitled folder")
            try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for pane in activePanes { pane.directoryContents.reload() }
        }
        toolbar.onGetInfo = {
            if let first = selectedItems.first {
                FileContextMenu.showInfo(for: first)
            }
        }
        toolbar.onQuickLook = { quickLook() }
        toolbar.onTerminal = {
            Task {
                try? await TerminalService.shared.openTerminal(
                    at: activeTab.navigationHistory.currentURL,
                    emulator: TerminalService.shared.defaultTerminal()
                )
            }
        }
        toolbar.onNewTab = {
            TabRestoreQueue.shared.enqueue(activeTab.navigationHistory.currentURL)
            openWindow(id: "browser")
        }
        toolbar.onApplyTag = { name, hex in
            let urls = selectedItems.map(\.url)
            guard !urls.isEmpty else { return }
            Task {
                do {
                    let all = (try? await TagService.shared.allTags()) ?? []
                    let tag: TagItem
                    if let existing = all.first(where: { $0.name.lowercased() == name.lowercased() }) {
                        tag = existing
                    } else {
                        tag = try await TagService.shared.createTag(name: name, colorHex: hex)
                    }
                    for url in urls {
                        try await TagService.shared.applyTag(tag.id, to: url)
                    }
                    await MainActor.run {
                        for pane in activePanes {
                            pane.directoryContents.reload()
                        }
                    }
                } catch {
                    NSLog("Failed to apply tag: %@", error.localizedDescription)
                }
            }
        }
        toolbar.onRename = { renameSelection() }
        toolbar.onBatchRename = { batchRenameSelection() }
        toolbar.onTrash = { trashSelection() }
        toolbar.onTogglePathBar = { showPathBar.toggle() }
        toolbar.onSearch = { query in
            if query.isEmpty {
                activeTab.directoryContents.reload()
            } else {
                activeTab.directoryContents.items = activeTab.directoryContents.items.filter {
                    $0.name.localizedCaseInsensitiveContains(query)
                }
            }
        }
        syncToolbar()
    }

    /// Switches icon/list view and persists the choice (Prompts 12, 16).
    private func setViewMode(_ mode: ViewMode) {
        activeTab.viewMode = mode
        toolbar.viewMode = mode
        toolbar.refresh()
        persistViewState()
    }

    /// Flips hidden-file visibility and reloads (Prompts 7, 16).
    private func toggleHiddenFiles() {
        showHiddenFiles.toggle()
        for pane in activePanes {
            pane.directoryContents.showHiddenFiles = showHiddenFiles
            pane.directoryContents.reload()
        }
        toolbar.showsHiddenFiles = showHiddenFiles
        toolbar.refresh()
        persistViewState()
    }

    /// Sets the multi-pane split layout (F-004).
    private func setSplitLayout(_ layout: SplitLayout) {
        splitLayout = layout
        let requiredCount = layout.paneCount
        while panes.count < requiredCount {
            let seedURL = activeTab.navigationHistory.currentURL
            let newTab = TabState(url: seedURL)
            newTab.directoryContents.showHiddenFiles = showHiddenFiles
            newTab.directoryContents.reload()
            panes.append(newTab)
        }
        for pane in activePanes {
            if pane.directoryContents.items.isEmpty && pane.directoryContents.error == nil {
                pane.directoryContents.reload()
            }
        }
        if activePaneIndex >= requiredCount {
            activePaneIndex = 0
        }
        syncToolbar()
    }

    /// Toggles between single pane and dual pane.
    private func toggleDualPane() {
        if splitLayout == .single {
            setSplitLayout(.horizontal2)
        } else {
            setSplitLayout(.single)
        }
    }

    /// Cycles to the next pane (Option+Tab).
    private func cycleNextPane() {
        guard splitLayout != .single else { return }
        activePaneIndex = (activePaneIndex + 1) % splitLayout.paneCount
        syncToolbar()
    }

    /// Mirrors SwiftUI state into the toolbar and revalidates its items.
    private func syncToolbar() {
        toolbar.canGoBack = activeTab.navigationHistory.canGoBack
        toolbar.canGoForward = activeTab.navigationHistory.canGoForward
        toolbar.hasSelection = !selectedItems.isEmpty
        toolbar.currentURL = activeTab.navigationHistory.currentURL
        toolbar.splitLayout = splitLayout
        toolbar.viewMode = activeTab.viewMode
        toolbar.iconSize = iconSize
        toolbar.showsHiddenFiles = showHiddenFiles
        toolbar.currentSortKey = activeTab.directoryContents.sortKey
        toolbar.sortAscending = activeTab.directoryContents.sortAscending
        toolbar.refresh()
        updateWindowTitle()
    }

    /// Space: Quick Look the selected item (Prompt 9).
    private func quickLook() {
        quickLook(for: activeTab)
    }

    private func quickLook(for currentTab: TabState) {
        let items = currentTab.directoryContents.items
        let selection = currentTab.selectionModel
        let anchor = selection.lastClickedID ?? selection.selectedIDs.first
        guard let anchor, let index = items.firstIndex(where: { $0.id == anchor }) else {
            QuickLookService.shared.hidePreview()
            return
        }
        QuickLookService.shared.togglePreview(for: items.map(\.url), selectedIndex: index)
    }

    // MARK: - File operations (Prompt 10)

    private var selectedItems: [FileItem] {
        activeTab.directoryContents.items.filter { activeTab.selectionModel.selectedIDs.contains($0.id) }
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
        let destination = activeTab.navigationHistory.currentURL
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
            for pane in activePanes {
                pane.directoryContents.reload()
            }
            activeTab.selectionModel.deselectAll()
            registerRestoreUndo(name: "Move to Trash", transfers: result.transfers)
            if let (_, error) = result.failed.first { showError("Move to Trash Failed", error: error) }
        }
    }

    /// Return/Enter or context menu: single rename or batch rename sheet.
    private func renameSelection() {
        let selected = selectedItems
        if selected.count == 1, let item = selected.first {
            renameText = item.name
            renameTarget = item
        } else if selected.count > 1 {
            batchRenameTargets = selected
            showBatchRenameSheet = true
        }
    }

    private func batchRenameSelection() {
        let selected = selectedItems
        guard !selected.isEmpty else { return }
        batchRenameTargets = selected
        showBatchRenameSheet = true
    }

    private func applyBatchRename(_ renames: [(url: URL, newName: String)]) {
        runFileOperation("Batch Rename") { progress in
            await FileOperationService.shared.renameItems(renames, progress: progress)
        } onCompletion: { result in
            registerRestoreUndo(name: "Batch Rename", transfers: result.transfers)
        }
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
            for pane in activePanes {
                pane.directoryContents.reload()
            }
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
                for pane in activePanes {
                    pane.directoryContents.reload()
                }
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
                for pane in activePanes {
                    pane.directoryContents.reload()
                }
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

    private var statusBarInfo: some View {
        let count = activeTab.directoryContents.items.count
        let selectedCount = activeTab.selectionModel.selectedIDs.count
        return HStack(spacing: 4) {
            if selectedCount > 0 {
                Text("\(selectedCount) of \(count) selected")
            } else {
                Text("\(count) item\(count == 1 ? "" : "s")")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// Enables native window tabbing and registers the window so its current
    /// directory can be saved on quit.
    private func configureWindow(_ window: NSWindow) {
        window.tabbingMode = .preferred
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        if window.frame.size.width < 960 || window.frame.size.height < 580 {
            var frame = window.frame
            frame.size.width = max(frame.size.width, 1060)
            frame.size.height = max(frame.size.height, 680)
            window.setFrame(frame, display: true, animate: false)
        }
        WindowTabRegistry.shared.register(window) { [activeTab] in
            activeTab.navigationHistory.currentURL
        }
        updateWindowTitle(for: window)
    }

    private func updateWindowTitle(for window: NSWindow? = nil) {
        guard let win = window ?? NSApp.keyWindow else { return }
        let currentURL = activeTab.navigationHistory.currentURL
        let titleName = currentURL.path == FileManager.default.homeURL.path
            ? "Home"
            : (currentURL.lastPathComponent.isEmpty ? "Macintosh HD" : currentURL.lastPathComponent)
        win.title = titleName
        win.representedURL = currentURL
    }

    /// Persistent banner shown while Full Disk Access is missing (Prompt 15).
    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Nautica has limited disk access. Some system folders may require Full Disk Access.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Settings…") {
                FullDiskAccess.openSystemSettings()
            }
            .buttonStyle(.link)
            .font(.subheadline)

            Button {
                withAnimation { dismissedFullDiskBanner = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
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
