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
    var newFolderWithSelection: () -> Void
    var duplicateSelection: () -> Void
    var makeAlias: () -> Void
    var showOriginal: () -> Void
    var undo: () -> Void
    var redo: () -> Void
    var getInfo: () -> Void
    var quickLook: () -> Void
    // Navigation (Go menu, Prompt 16).
    var goBack: () -> Void
    var goForward: () -> Void
    var goToEnclosingFolder: () -> Void
    var navigateTo: (URL) -> Void
    /// "Go to Folder…" prompt.
    var promptGoToFolder: () -> Void
    /// "Connect to Server…" prompt (Cmd+K).
    var promptConnectToServer: () -> Void
    // View menu (Prompt 16).
    var setViewMode: (ViewMode) -> Void
    var toggleHiddenFiles: () -> Void
    var setGroupBy: (GroupByCriterion) -> Void
    var showViewOptions: () -> Void
    var putBack: () -> Void
    /// Sets multi-pane split layout (F-004).
    var setSplitLayout: (SplitLayout) -> Void
    /// Toggles between single pane and dual pane.
    var toggleDualPane: () -> Void
    /// Cycles to the next pane (Option+Tab).
    var cycleNextPane: () -> Void
    /// Toggles the bottom path bar (Option+Command+P).
    var togglePathBar: () -> Void
    /// Toggles the left sidebar.
    var toggleSidebar: () -> Void
    /// Toggles the right-hand tree panel.
    var toggleTreePanel: () -> Void
    /// Toggles the right-hand inspector.
    var toggleInspector: () -> Void
    /// Shows a specific inspector tab.
    var showInspectorTab: (RightSidebarTab) -> Void
    // Window and Tab operations (Phase 8).
    var duplicateTab: () -> Void
    var closeOtherTabs: () -> Void
    var closeTabsToTheRight: () -> Void
    var moveTabToNewWindow: () -> Void
    var mergeAllWindows: () -> Void
    // Dual-pane Commander operations (Phase 8).
    var copyToInactivePane: () -> Void
    var moveToInactivePane: () -> Void
    var toggleSyncNavigation: () -> Void
    // Instant in-folder filter bar (Phase 9).
    var toggleFilterBar: () -> Void
    // macOS Color Labels & Finder Tags (Phase 9).
    var toggleTag: (TagColor) -> Void
    var clearTags: () -> Void
    // Cloud storage operations (Phase 10).
    var downloadCloudSelection: () -> Void
    var evictCloudSelection: () -> Void
    // Checksums & Duplicate Finder (Phase 11).
    var copySHA256Checksum: () -> Void
    var findDuplicatesInFolder: () -> Void
    // Git integration (Phase 12).
    var gitDiffSelection: () -> Void
    var gitStageSelection: () -> Void
    var gitUnstageSelection: () -> Void
    var gitDiscardSelection: () -> Void
    var gitCommit: () -> Void
    var gitSwitchBranch: (String) -> Void
    var gitCreateBranch: () -> Void
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
    @State private var searchText = ""
    @State private var searchCriteria: [SearchCriterion] = []
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
    @State private var showConnectToServerSheet = false
    @State private var showCompressPasswordSheet = false
    @State private var compressPasswordTargets: [URL] = []
    @State private var showDuplicateFinderSheet = false
    @State private var duplicateFinderTargetDirectory: URL? = nil
    @State private var showGitDiffSheet = false
    @State private var showGitCommitSheet = false
    @State private var gitDiffTargetURL: URL? = nil
    @State private var conflictSheetData: ConflictSheetData?
    @State private var searchScope: SearchScope = .folder(Constants.defaultWindowURL())
    @State private var searchFilter: SearchFilter = .nameAndContent
    @State private var isSearchActive = false
    @AppStorage("showPathBar") private var showPathBar = true
    /// Right-hand inspector panel.
    @AppStorage("showRightSidebar") private var showRightSidebar = true
    @AppStorage("Nautica.RightSidebar.ActiveTab") private var rightSidebarTab: RightSidebarTab = .recents
    @State private var stagedURLs: [URL] = []
    @State private var showFilterBar = false
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

    private var inactivePane: TabState? {
        guard splitLayout != .single, splitLayout.paneCount > 1 else { return nil }
        let otherIndex = (activePaneIndex == 0) ? 1 : 0
        guard otherIndex < splitLayout.paneCount && panes.indices.contains(otherIndex) else { return nil }
        return panes[otherIndex]
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContentView
        } detail: {
            detailContentView
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $showRightSidebar) {
            inspectorContentView
        }
        .frame(minWidth: 720, minHeight: 450)
        .background(WindowAccessor(onWindow: configureWindow))
        .focusedSceneValue(\.browserURL, activeTab.navigationHistory.currentURL)
        .focusedSceneValue(\.browserActions, currentBrowserActions)
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
        .sheet(isPresented: $showConnectToServerSheet) {
            ConnectToServerSheet { mountedURL in
                navigate(to: mountedURL)
            }
        }
        .toolSheets(
            showCompressPassword: $showCompressPasswordSheet,
            compressPasswordCount: compressPasswordTargets.count,
            onCompressPassword: { password in
                compressSelectionWithPassword(password: password)
            },
            showDuplicateFinder: $showDuplicateFinderSheet,
            duplicateFinderDirectory: duplicateFinderTargetDirectory ?? activeTab.navigationHistory.currentURL,
            onTrashDuplicates: { urls in
                trashDuplicateURLs(urls)
            }
        )
        .gitSheets(
            showDiff: $showGitDiffSheet,
            showCommit: $showGitCommitSheet,
            targetURL: gitDiffTargetURL,
            repoURL: activeTab.navigationHistory.currentURL,
            onReload: {
                activeTab.directoryContents.reload()
            }
        )
        .sheet(item: $conflictSheetData) { data in
            ConflictResolutionSheet(
                model: data.model,
                onComplete: { resolutions in
                    let model = data.model
                    let sources = data.sources
                    conflictSheetData = nil
                    executeTransfer(
                        sources: sources,
                        destination: model.destination,
                        move: model.isMove,
                        resolutions: resolutions
                    )
                },
                onCancel: {
                    conflictSheetData = nil
                }
            )
        }
        .onAppear {
            if viewStateService == nil {
                viewStateService = ViewStateService(context: modelContext)
                activeTab.directoryContents.onSortChanged = persistViewState
            }
            restoreIfPending()
            applyViewState(for: activeTab.navigationHistory.currentURL)
            showPermissionBanner = !FullDiskAccess.isGranted
        }
        .onChange(of: iconSize) { persistViewState() }
        .onChange(of: searchText) { performSearch(searchText) }
        .onChange(of: searchScope) { performSearch(searchText) }
        .onChange(of: searchFilter) { performSearch(searchText) }
        .onChange(of: searchCriteria) { performSearch(searchText) }
        .task {
            for pane in activePanes {
                pane.directoryContents.reload()
            }
        }
    }

    @ToolbarContentBuilder
    private var mainToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            ControlGroup {
                Button(action: goBack) {
                    Label("Back", systemImage: "chevron.backward")
                }
                .disabled(!activeTab.navigationHistory.canGoBack)
                .help("Back (⌘[)")

                Button(action: goForward) {
                    Label("Forward", systemImage: "chevron.forward")
                }
                .disabled(!activeTab.navigationHistory.canGoForward)
                .help("Forward (⌘])")
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Picker("View Mode", selection: Binding(
                get: { activeTab.viewMode },
                set: { setViewMode($0) }
            )) {
                Image(systemName: "square.grid.2x2").tag(ViewMode.icon)
                Image(systemName: "list.bullet").tag(ViewMode.list)
                Image(systemName: "rectangle.split.3x1").tag(ViewMode.column)
            }
            .pickerStyle(.segmented)
            .help("View as Icons, List, or Columns (⌘1, ⌘2, ⌘3)")

            Menu {
                Button {
                    setSplitLayout(.single)
                } label: {
                    Label("Single Pane", systemImage: "rectangle")
                }
                Divider()
                Button {
                    setSplitLayout(.horizontal2)
                } label: {
                    Label("2 Panes (Side by Side)", systemImage: "rectangle.split.2x1")
                }
                Button {
                    setSplitLayout(.vertical2)
                } label: {
                    Label("2 Panes (Stacked)", systemImage: "rectangle.split.1x2")
                }
                Divider()
                Button {
                    setSplitLayout(.quad4)
                } label: {
                    Label("4 Panes (Grid)", systemImage: "rectangle.split.2x2")
                }
                Button {
                    setSplitLayout(.horizontal4)
                } label: {
                    Label("4 Panes (Columns)", systemImage: "rectangle.split.3x1")
                }
                Button {
                    setSplitLayout(.vertical4)
                } label: {
                    Label("4 Panes (Rows)", systemImage: "rectangle.split.1x2")
                }
            } label: {
                Image(systemName: splitLayoutIcon)
            }
            .help("Panes Layout")

            Menu {
                Section("Arrange By") {
                    ForEach(GroupByCriterion.allCases) { criterion in
                        Button {
                            activeTab.directoryContents.groupBy = criterion
                            persistViewState()
                        } label: {
                            HStack {
                                Text(criterion.title)
                                if activeTab.directoryContents.groupBy == criterion {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Divider()
                Section("Sort By") {
                    ForEach(SortKey.allCases, id: \.self) { key in
                        Button {
                            activeTab.directoryContents.sort(by: key, ascending: activeTab.directoryContents.sortAscending)
                            persistViewState()
                        } label: {
                            HStack {
                                Text("Sort by \(key.title)")
                                if activeTab.directoryContents.sortKey == key {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        activeTab.directoryContents.sort(by: activeTab.directoryContents.sortKey, ascending: !activeTab.directoryContents.sortAscending)
                        persistViewState()
                    } label: {
                        HStack {
                            Text(activeTab.directoryContents.sortAscending ? "Ascending" : "Descending")
                            Image(systemName: activeTab.directoryContents.sortAscending ? "arrow.up" : "arrow.down")
                        }
                    }
                }
            } label: {
                Image(systemName: "square.grid.3x1.below.line.grid.1x2")
            }
            .help("Group and Sort Items")

            Button(action: shareSelection) {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(selectedItems.isEmpty)
            .help("Share selected items")

            Menu {
                ForEach(tagColors, id: \.0) { name, hex in
                    Button {
                        applyTag(name, hex: hex)
                    } label: {
                        Label {
                            Text(name)
                        } icon: {
                            Image(nsImage: tagDotImage(for: hex))
                        }
                    }
                }
            } label: {
                Image(systemName: "tag")
            }
            .disabled(selectedItems.isEmpty)
            .help("Edit Tags")

            Menu {
                Button(action: newFolder) {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                Divider()
                Button(action: getInfo) {
                    Label("Get Info", systemImage: "info.circle")
                }
                .disabled(selectedItems.isEmpty)

                Button(action: { quickLook() }) {
                    Label("Quick Look", systemImage: "eye")
                }
                .disabled(selectedItems.isEmpty)

                Divider()
                Button(action: renameSelection) {
                    Label("Rename…", systemImage: "pencil")
                }
                .disabled(selectedItems.isEmpty)

                Button(action: batchRenameSelection) {
                    Label("Batch Rename…", systemImage: "pencil.and.list.clipboard")
                }
                .disabled(selectedItems.isEmpty)

                Button(action: trashSelection) {
                    Label("Move to Trash", systemImage: "trash")
                }
                .disabled(selectedItems.isEmpty)

                if let first = selectedItems.first, TrashOriginStore.shared.canPutBack(url: first.url) {
                    Button(action: putBackSelection) {
                        Label("Put Back", systemImage: "arrow.uturn.backward")
                    }
                }

                Divider()
                Button(action: toggleViewOptions) {
                    Label("Show View Options", systemImage: "slider.horizontal.3")
                }

                Divider()
                Button(action: openTerminal) {
                    Label("Open in Terminal", systemImage: "terminal")
                }

                Button(action: toggleHiddenFiles) {
                    Label(showHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files", systemImage: "eye.slash")
                }

                Button(action: { showPathBar.toggle() }) {
                    Label(showPathBar ? "Hide Path Bar" : "Show Path Bar", systemImage: "character.textbox")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("Action")

            Button(action: newFolder) {
                Image(systemName: "folder.badge.plus")
            }
            .help("New Folder (⇧⌘N)")

            Button(action: { showRightSidebar.toggle() }) {
                Image(systemName: "sidebar.right")
            }
            .help(showRightSidebar ? "Hide Inspector (⌥⌘I)" : "Show Inspector (⌥⌘I)")
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
                HorizontalSplit {
                    paneView(for: panes[0], index: 0)
                } right: {
                    paneView(for: panes[1], index: 1)
                }
            } else if let first = panes.first {
                paneView(for: first, index: 0)
            }

        case .vertical2:
            if panes.count >= 2 {
                VerticalSplit {
                    paneView(for: panes[0], index: 0)
                } bottom: {
                    paneView(for: panes[1], index: 1)
                }
            } else if let first = panes.first {
                paneView(for: first, index: 0)
            }

        case .quad4:
            if panes.count >= 4 {
                VerticalSplit {
                    HorizontalSplit {
                        paneView(for: panes[0], index: 0)
                    } right: {
                        paneView(for: panes[1], index: 1)
                    }
                } bottom: {
                    HorizontalSplit {
                        paneView(for: panes[2], index: 2)
                    } right: {
                        paneView(for: panes[3], index: 3)
                    }
                }
            } else if let first = panes.first {
                paneView(for: first, index: 0)
            }

        case .horizontal4:
            if panes.count >= 4 {
                HorizontalSplit {
                    paneView(for: panes[0], index: 0)
                } right: {
                    HorizontalSplit {
                        paneView(for: panes[1], index: 1)
                    } right: {
                        HorizontalSplit {
                            paneView(for: panes[2], index: 2)
                        } right: {
                            paneView(for: panes[3], index: 3)
                        }
                    }
                }
            } else if let first = panes.first {
                paneView(for: first, index: 0)
            }

        case .vertical4:
            if panes.count >= 4 {
                VerticalSplit {
                    paneView(for: panes[0], index: 0)
                } bottom: {
                    VerticalSplit {
                        paneView(for: panes[1], index: 1)
                    } bottom: {
                        VerticalSplit {
                            paneView(for: panes[2], index: 2)
                        } bottom: {
                            paneView(for: panes[3], index: 3)
                        }
                    }
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
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isFocused ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()

                    if isFocused {
                        HStack(spacing: 6) {
                            Button {
                                copyToInactivePane()
                            } label: {
                                Label("F5 Copy", systemImage: "arrow.right.doc.on.clipboard")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .buttonStyle(.borderless)
                            .help("Copy selected items to inactive pane (F5)")

                            Button {
                                moveToInactivePane()
                            } label: {
                                Label("F6 Move", systemImage: "arrow.right")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .buttonStyle(.borderless)
                            .help("Move selected items to inactive pane (F6)")

                            Button {
                                toggleSyncNavigation()
                            } label: {
                                Image(systemName: SyncNavigationManager.shared.isSyncNavigationEnabled ? "link.circle.fill" : "link.circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SyncNavigationManager.shared.isSyncNavigationEnabled ? Color.accentColor : .secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Toggle Synchronized Navigation (⌥⌘S)")
                        }
                    }

                    Text("Active")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color.accentColor.opacity(0.14))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                        .opacity(isFocused ? 1 : 0)
                        .accessibilityHidden(!isFocused)
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Color(NSColor.controlBackgroundColor))
                .contentShape(Rectangle())
                .onHover { isHovered in
                    if isHovered { activatePane(index) }
                }
                .onTapGesture {
                    activatePane(index)
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
                    onNavigateToParent: {
                        let current = currentTab.navigationHistory.currentURL
                        let parent = current.deletingLastPathComponent()
                        if parent.path != current.path {
                            navigate(to: parent, in: currentTab)
                        }
                    },
                    onOpenSelection: {
                        openSelection(in: currentTab)
                    },
                    onCopyPath: {
                        copyPathsToPasteboard(for: currentTab)
                    },
                    onToggleHiddenFiles: {
                        showHiddenFiles.toggle()
                        for pane in activePanes {
                            pane.directoryContents.showHiddenFiles = showHiddenFiles
                            pane.directoryContents.reload()
                        }
                    },
                    onGoToFolder: {
                        showGoToFolderSheet = true
                    },
                    onRenameRequest: renameSelection,
                    onCopySelection: copySelectionToPasteboard,
                    onTrashSelection: trashSelection,
                    onDuplicate: duplicateSelection,
                    onMakeAlias: makeAliasSelection,
                    onShowOriginal: showOriginalSelection,
                    onPaste: { pasteFromPasteboard(move: false) },
                    onMoveHere: { pasteFromPasteboard(move: true) },
                    onNewFolderWithSelection: newFolderWithSelection,
                    onUndo: { activeUndoManager?.undo() },
                    onRedo: { activeUndoManager?.redo() },
                    onGetInfo: getInfo,
                    onPutBack: putBackSelection,
                    onConnectToServer: { showConnectToServerSheet = true },
                    onCompressWithPassword: { urls in
                        compressPasswordTargets = urls
                        showCompressPasswordSheet = true
                    },
                    onFindDuplicates: { url in
                        duplicateFinderTargetDirectory = url
                        showDuplicateFinderSheet = true
                    },
                    onGitDiff: { url in
                        gitDiffTargetURL = url
                        showGitDiffSheet = true
                    },
                    onGitCommit: {
                        showGitCommitSheet = true
                    },
                    onQuickCopyToOtherPane: { copyToInactivePane() },
                    onQuickMoveToOtherPane: { moveToInactivePane() },
                    onCyclePane: { cycleNextPane() },
                    onToggleTag: toggleColorTagOnSelection,
                    onClearTags: clearTagsOnSelection,
                    setViewMode: setViewMode,
                    isFocused: isFocused,
                    onMouseEnter: { activatePane(index) }
                )
                .overlay(
                    Rectangle()
                        .strokeBorder(splitLayout != .single && isFocused ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
                )
            }
        }
        .frame(minWidth: 160, minHeight: 120)
        .contentShape(Rectangle())
        .onHover { isHovered in
            if isHovered { activatePane(index) }
        }
        .onTapGesture {
            activatePane(index)
        }
        .onChange(of: currentTab.selectionModel.selectedIDs) {
            if !currentTab.selectionModel.selectedIDs.isEmpty {
                activatePane(index)
            }
        }
    }

    private func activatePane(_ index: Int) {
        guard activePaneIndex != index, panes.indices.contains(index) else { return }
        activePaneIndex = index
        syncToolbar()
    }

    private func syncInactivePaneIfEnabled(from previousURL: URL, to newURL: URL) {
        guard SyncNavigationManager.shared.isSyncNavigationEnabled,
              splitLayout != .single,
              let other = inactivePane else { return }
        let pairedCurrent = other.navigationHistory.currentURL
        if let syncURL = SyncNavigationManager.shared.synchronizedURL(toURL: newURL, fromURL: previousURL, pairedCurrentURL: pairedCurrent) {
            other.navigationHistory.navigate(to: syncURL)
            show(syncURL, in: other)
        }
    }

    /// Single navigation entry point: sidebar, path bar, and double-click on a
    /// folder all route here. Pushes history, then shows the new location.
    private func navigate(to url: URL) {
        navigate(to: url, in: activeTab)
    }

    private func navigate(to url: URL, in targetTab: TabState) {
        let previousURL = targetTab.navigationHistory.currentURL
        targetTab.navigationHistory.navigate(to: url)
        show(url, in: targetTab)
        if targetTab === activeTab {
            syncInactivePaneIfEnabled(from: previousURL, to: url)
        }
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
            ViewOptionsService.shared.sync(
                folderURL: url,
                viewMode: targetTab.viewMode,
                iconSize: CGFloat(iconSize),
                groupBy: targetTab.directoryContents.groupBy
            )
        }
    }

    /// Restores the persisted per-folder view state (Prompt 12), if any.
    private func applyViewState(for url: URL) {
        guard let state = viewStateService?.state(for: url.path) else { return }
        activeTab.viewMode = ViewMode(rawValue: state.viewMode) ?? .icon
        showHiddenFiles = state.showHiddenFiles
        activeTab.directoryContents.sortKey = SortKey(rawValue: state.sortKey) ?? .name
        activeTab.directoryContents.sortAscending = state.sortAscending
        if let groupByRaw = state.groupBy, let criterion = GroupByCriterion(rawValue: groupByRaw) {
            activeTab.directoryContents.groupBy = criterion
        } else {
            activeTab.directoryContents.groupBy = .none
        }
    }

    /// Mirrors the current view settings into the folder's state and saves
    /// after a 500 ms quiet period (Prompt 12).
    private func persistViewState() {
        guard let state = viewStateService?.current else { return }
        state.viewMode = activeTab.viewMode.rawValue
        state.sortKey = activeTab.directoryContents.sortKey.rawValue
        state.sortAscending = activeTab.directoryContents.sortAscending
        state.showHiddenFiles = showHiddenFiles
        state.groupBy = activeTab.directoryContents.groupBy.rawValue
        viewStateService?.scheduleSave()
        ViewOptionsService.shared.sync(
            folderURL: activeTab.navigationHistory.currentURL,
            viewMode: activeTab.viewMode,
            iconSize: CGFloat(iconSize),
            groupBy: activeTab.directoryContents.groupBy
        )
    }

    private func goBack() {
        let previousURL = activeTab.navigationHistory.currentURL
        guard let url = activeTab.navigationHistory.goBack() else { return }
        show(url, in: activeTab)
        syncInactivePaneIfEnabled(from: previousURL, to: url)
    }

    private func goForward() {
        let previousURL = activeTab.navigationHistory.currentURL
        guard let url = activeTab.navigationHistory.goForward() else { return }
        show(url, in: activeTab)
        syncInactivePaneIfEnabled(from: previousURL, to: url)
    }

    private func setViewMode(_ mode: ViewMode) {
        activeTab.viewMode = mode
        persistViewState()
    }

    private func toggleHiddenFiles() {
        showHiddenFiles.toggle()
        for pane in activePanes {
            pane.directoryContents.showHiddenFiles = showHiddenFiles
            pane.directoryContents.reload()
        }
        persistViewState()
    }

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

    private func toggleDualPane() {
        if splitLayout == .single {
            setSplitLayout(.horizontal2)
        } else {
            setSplitLayout(.single)
        }
    }

    private func toggleSidebar() {
        withAnimation {
            columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
        }
    }

    private func cycleNextPane() {
        guard splitLayout != .single else { return }
        activePaneIndex = (activePaneIndex + 1) % splitLayout.paneCount
        syncToolbar()
    }

    private func duplicateTab() {
        let currentURL = activeTab.navigationHistory.currentURL
        TabRestoreQueue.shared.enqueue(currentURL)
        openWindow(id: "browser")
    }

    private func closeOtherTabs() {
        WindowTabManager.shared.closeOtherTabs()
    }

    private func closeTabsToTheRight() {
        WindowTabManager.shared.closeTabsToTheRight()
    }

    private func moveTabToNewWindow() {
        WindowTabManager.shared.moveTabToNewWindow()
    }

    private func mergeAllWindows() {
        WindowTabManager.shared.mergeAllWindows()
    }

    private func transferToInactivePane(move: Bool) {
        guard let destination = inactivePane?.navigationHistory.currentURL else { return }
        let sources = selectedItems.map(\.url)
        guard !sources.isEmpty else { return }
        let collisions = FileOperationService.shared.detectCollisions(sources: sources, destination: destination)
        if !collisions.isEmpty {
            conflictSheetData = ConflictSheetData(
                sources: sources,
                model: ConflictResolutionModel(conflicts: collisions, isMove: move, destination: destination)
            )
            return
        }
        executeTransfer(sources: sources, destination: destination, move: move, resolutions: [:])
    }

    private func copyToInactivePane() {
        transferToInactivePane(move: false)
    }

    private func moveToInactivePane() {
        transferToInactivePane(move: true)
    }

    private func toggleSyncNavigation() {
        SyncNavigationManager.shared.toggle()
    }

    private func syncToolbar() {
        updateWindowTitle()
    }

    private func newFolder() {
        let parentURL = activeTab.navigationHistory.currentURL
        let fm = FileManager.default
        var folderName = "untitled folder"
        var destination = parentURL.appendingPathComponent(folderName)
        var counter = 2
        while fm.fileExists(atPath: destination.path) {
            folderName = "untitled folder \(counter)"
            destination = parentURL.appendingPathComponent(folderName)
            counter += 1
        }
        do {
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            registerDeleteUndo(name: "New Folder", urls: [destination])
            for pane in activePanes { pane.directoryContents.reload() }
            activeTab.selectionModel.deselectAll()
            if let newItem = activeTab.directoryContents.items.first(where: { $0.url == destination }) {
                activeTab.selectionModel.select(newItem.id, modifierFlags: [])
                renameTarget = newItem
                renameText = newItem.name
            }
        } catch {
            showError("Folder Creation Failed", error: error)
        }
    }

    private func duplicateSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        runFileOperation(urls.count == 1 ? "Duplicating Item" : "Duplicating Items") { progress in
            await FileOperationService.shared.duplicateItems(urls, progress: progress)
        } onCompletion: { result in
            registerDeleteUndo(name: "Duplicate", urls: result.succeeded)
            for pane in activePanes {
                pane.directoryContents.reload()
            }
            if !result.succeeded.isEmpty {
                let destSet = Set(result.succeeded)
                activeTab.selectionModel.deselectAll()
                for item in activeTab.directoryContents.items where destSet.contains(item.url) {
                    activeTab.selectionModel.select(item.id, modifierFlags: [.command])
                }
            }
        }
    }

    private func makeAliasSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        let destination = activeTab.navigationHistory.currentURL
        runFileOperation(urls.count == 1 ? "Creating Alias" : "Creating Aliases") { _ in
            await FileOperationService.shared.makeAliases(for: urls, in: destination)
        } onCompletion: { result in
            registerDeleteUndo(name: "Make Alias", urls: result.succeeded)
            for pane in activePanes {
                pane.directoryContents.reload()
            }
            if !result.succeeded.isEmpty {
                let destSet = Set(result.succeeded)
                activeTab.selectionModel.deselectAll()
                for item in activeTab.directoryContents.items where destSet.contains(item.url) {
                    activeTab.selectionModel.select(item.id, modifierFlags: [.command])
                }
            }
        }
    }

    private func showOriginalSelection() {
        guard let item = selectedItems.first else { return }
        let targetURL = item.resolvedTargetURL ?? FileOperationService.shared.resolveTarget(for: item.url)
        guard let targetURL else { return }

        let parentURL = targetURL.deletingLastPathComponent().standardizedFileURL
        let currentParent = activeTab.navigationHistory.currentURL.standardizedFileURL

        if currentParent.path == parentURL.path {
            activeTab.selectionModel.deselectAll()
            if let targetItem = activeTab.directoryContents.items.first(where: { $0.url.standardizedFileURL.path == targetURL.standardizedFileURL.path }) {
                activeTab.selectionModel.select(targetItem.id, modifierFlags: [])
            }
        } else {
            navigate(to: parentURL)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.activeTab.selectionModel.deselectAll()
                if let targetItem = self.activeTab.directoryContents.items.first(where: { $0.url.standardizedFileURL.path == targetURL.standardizedFileURL.path }) {
                    self.activeTab.selectionModel.select(targetItem.id, modifierFlags: [])
                }
            }
        }
    }

    private func rotateSelection(by degrees: Int) {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        Task {
            for url in urls {
                await QuickActionService.shared.rotateImage(at: url, degrees: degrees)
            }
            await MainActor.run {
                for pane in activePanes {
                    pane.directoryContents.reload()
                }
            }
        }
    }

    private func createPDFFromSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        let currentFolder = activeTab.navigationHistory.currentURL
        Task {
            if let pdfURL = try? await QuickActionService.shared.createPDF(from: urls, in: currentFolder) {
                await MainActor.run {
                    for pane in activePanes {
                        pane.directoryContents.reload()
                    }
                    activeTab.selectionModel.deselectAll()
                    if let newItem = activeTab.directoryContents.items.first(where: { $0.url.standardizedFileURL.path == pdfURL.standardizedFileURL.path }) {
                        activeTab.selectionModel.select(newItem.id, modifierFlags: [])
                    }
                }
            }
        }
    }

    private func newFolderWithSelection() {
        let itemsToMove = selectedItems
        guard !itemsToMove.isEmpty else {
            newFolder()
            return
        }
        let parentURL = activeTab.navigationHistory.currentURL
        let fm = FileManager.default

        var folderName = "New Folder With Items"
        var folderURL = parentURL.appendingPathComponent(folderName)
        var counter = 2
        while fm.fileExists(atPath: folderURL.path) {
            folderName = "New Folder With Items \(counter)"
            folderURL = parentURL.appendingPathComponent(folderName)
            counter += 1
        }

        do {
            try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            showError("Folder Creation Failed", error: error)
            return
        }

        let urls = itemsToMove.map(\.url)
        runFileOperation("Moving Items to New Folder") { progress in
            await FileOperationService.shared.moveItems(urls, to: folderURL, progress: progress)
        } onCompletion: { result in
            registerNewFolderWithSelectionUndo(folderURL: folderURL, originalTransfers: result.transfers)
            for pane in activePanes {
                pane.directoryContents.reload()
            }
            activeTab.selectionModel.deselectAll()
            if let newItem = activeTab.directoryContents.items.first(where: { $0.url == folderURL }) {
                activeTab.selectionModel.select(newItem.id, modifierFlags: [])
                renameTarget = newItem
                renameText = newItem.name
            }
        }
    }

    private func getInfo() {
        let urls = selectedItems.map(\.url)
        if urls.isEmpty {
            GetInfoService.shared.showInfo(for: [activeTab.navigationHistory.currentURL])
        } else {
            GetInfoService.shared.showInfo(for: urls)
        }
    }

    private func openTerminal() {
        Task {
            try? await TerminalService.shared.openTerminal(
                at: activeTab.navigationHistory.currentURL,
                emulator: TerminalService.shared.defaultTerminal()
            )
        }
    }

    private func shareSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        let picker = NSSharingServicePicker(items: urls)
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
        }
    }

    private func applyTag(_ name: String, hex: String) {
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

    private func performSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && searchCriteria.isEmpty {
            SearchService.shared.stopSearch()
            isSearchActive = false
            activeTab.directoryContents.reload()
        } else {
            isSearchActive = true
            SearchService.shared.performSearch(
                query: trimmed,
                scope: searchScope,
                filter: searchFilter,
                criteria: searchCriteria,
                includingHidden: showHiddenFiles
            ) { [weak activeTab] results in
                guard let activeTab else { return }
                activeTab.directoryContents.items = results
            }
        }
    }

    private func dismissSearch() {
        searchText = ""
        searchCriteria = []
        isSearchActive = false
        SearchService.shared.stopSearch()
        activeTab.directoryContents.reload()
    }

    private func saveCurrentSearchAsSmartFolder(name: String) {
        do {
            let savedURL = try SearchService.shared.saveSmartFolder(
                name: name,
                query: searchText,
                scope: searchScope,
                criteria: searchCriteria
            )
            sidebarModel.addFavorite(url: savedURL)
        } catch {
            NSLog("Failed to save smart folder: %@", error.localizedDescription)
        }
    }

    private func tagDotImage(for hex: String) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        let img = NSImage(size: size, flipped: false) { rect in
            if let color = NSColor(hex: hex) {
                color.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                return true
            }
            return false
        }
        return img
    }

    private func toggleFilterBar() {
        showFilterBar.toggle()
        if !showFilterBar {
            activeTab.directoryContents.clearFilter()
        }
    }

    private func filterByTagFromSidebar(_ tag: TagItem) {
        searchScope = .localComputer
        searchCriteria = [SearchCriterion(attribute: .tags, tagValue: tag.name)]
        isSearchActive = true
        performSearch("")
    }

    private func toggleColorTagOnSelection(_ color: TagColor) {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        Task {
            try? await TagService.shared.toggleColorTag(color, for: urls)
            for pane in activePanes {
                pane.directoryContents.reload()
            }
        }
    }

    private func clearTagsOnSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        Task {
            try? await TagService.shared.clearAllTags(for: urls)
            for pane in activePanes {
                pane.directoryContents.reload()
            }
        }
    }

    private func downloadCloudSelection() {
        let targets = selectedItems.filter(\.canDownload)
        guard !targets.isEmpty else { return }
        Task {
            for item in targets {
                try? await CloudStorageService.downloadItem(at: item.url)
            }
            for pane in activePanes {
                pane.directoryContents.reload()
            }
        }
    }

    private func evictCloudSelection() {
        let targets = selectedItems.filter(\.canEvict)
        guard !targets.isEmpty else { return }
        Task {
            for item in targets {
                try? await CloudStorageService.evictItem(at: item.url)
            }
            for pane in activePanes {
                pane.directoryContents.reload()
            }
        }
    }

    private let tagColors: [(String, String)] = [
        ("Red", "#FF3B30"),
        ("Orange", "#FF9500"),
        ("Yellow", "#FFCC00"),
        ("Green", "#34C759"),
        ("Blue", "#007AFF"),
        ("Purple", "#AF52DE"),
        ("Gray", "#8E8E93"),
    ]

    private var splitLayoutIcon: String {
        switch splitLayout {
        case .single: return "rectangle"
        case .horizontal2: return "rectangle.split.2x1"
        case .vertical2: return "rectangle.split.1x2"
        case .quad4: return "rectangle.split.2x2"
        case .horizontal4: return "rectangle.split.3x1"
        case .vertical4: return "rectangle.split.1x2"
        }
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

    /// Cmd+Opt+C: copy selected file POSIX path strings to pasteboard.
    private func copyPathsToPasteboard(for tab: TabState) {
        let selected = tab.directoryContents.items.filter { tab.selectionModel.isSelected($0.id) }
        let text = selected.isEmpty ? tab.navigationHistory.currentURL.path : selected.map(\.url.path).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Cmd+Down / Cmd+O / Return: open selected item (drill into directory or launch file).
    private func openSelection(in tab: TabState) {
        let selected = tab.directoryContents.items.filter { tab.selectionModel.isSelected($0.id) }
        guard let first = selected.first else { return }
        if ArchiveService.shared.isArchive(url: first.url) {
            Task {
                do {
                    _ = try await ArchiveService.shared.extract(archiveURL: first.url)
                    await MainActor.run {
                        for pane in activePanes { pane.directoryContents.reload() }
                    }
                } catch {
                    await MainActor.run { showError("Extraction Failed", error: error) }
                }
            }
        } else if ArchiveService.shared.isDiskImage(url: first.url) {
            Task {
                do {
                    let mountPoint = try await ArchiveService.shared.attachDiskImage(at: first.url)
                    await MainActor.run { navigate(to: mountPoint, in: tab) }
                } catch {
                    await MainActor.run { showError("Mount Failed", error: error) }
                }
            }
        } else if first.isDirectory {
            navigate(to: first.url, in: tab)
        } else {
            for item in selected where !item.isDirectory {
                NSWorkspace.shared.open(item.url)
            }
        }
    }

    private func compressSelectionWithPassword(password: String) {
        let urls = compressPasswordTargets
        guard !urls.isEmpty else { return }
        let currentFolder = activeTab.navigationHistory.currentURL
        Task {
            do {
                _ = try await ArchiveService.shared.createArchive(from: urls, in: currentFolder, password: password)
                await MainActor.run {
                    for pane in activePanes {
                        pane.directoryContents.reload()
                    }
                }
            } catch {
                await MainActor.run {
                    showError("Compression Failed", error: error)
                }
            }
        }
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
        let collisions = FileOperationService.shared.detectCollisions(sources: sources, destination: destination)
        if !collisions.isEmpty {
            conflictSheetData = ConflictSheetData(
                sources: sources,
                model: ConflictResolutionModel(conflicts: collisions, isMove: move, destination: destination)
            )
            return
        }
        executeTransfer(sources: sources, destination: destination, move: move, resolutions: [:])
    }

    private func executeTransfer(
        sources: [URL],
        destination: URL,
        move: Bool,
        resolutions: [URL: ConflictResolutionChoice]
    ) {
        runFileOperation(move ? "Moving Files" : "Copying Files") { progress in
            move
                ? await FileOperationService.shared.moveItems(sources, to: destination, progress: progress, resolutions: resolutions)
                : await FileOperationService.shared.copyItems(sources, to: destination, progress: progress, resolutions: resolutions)
        } onCompletion: { result in
            // Undo of a move: put everything back where it came from.
            if move {
                registerRestoreUndo(
                    name: "Move", transfers: result.transfers
                )
            } else {
                registerDeleteUndo(
                    name: "Copy", urls: result.succeeded
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

    /// Finder "Put Back" (⌘⌫ in Trash / context menu): restores trashed items to original directories.
    private func putBackSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        Task {
            let result = await TrashOriginStore.shared.putBack(urls: urls)
            for pane in activePanes {
                pane.directoryContents.reload()
            }
            activeTab.selectionModel.deselectAll()
            if let (_, error) = result.failed.first {
                showError("Put Back Failed", error: error)
            }
        }
    }

    /// Copies SHA-256 checksum of the selected file to pasteboard (Phase 11).
    private func copySHA256ChecksumForSelection() {
        guard let item = selectedItems.first, !item.isDirectory else { return }
        Task {
            if let hash = try? await ChecksumService.shared.computeSHA256(url: item.url) {
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(hash, forType: .string)
                }
            }
        }
    }

    /// Opens Duplicate Finder sheet for current folder (Phase 11).
    private func findDuplicatesInCurrentFolder() {
        duplicateFinderTargetDirectory = activeTab.navigationHistory.currentURL
        showDuplicateFinderSheet = true
    }

    /// Trashes selected duplicates with full undo registration (Phase 11).
    private func trashDuplicateURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            let result = await FileOperationService.shared.trashItems(urls)
            for pane in activePanes {
                pane.directoryContents.reload()
            }
            registerRestoreUndo(name: "Trash Duplicates", transfers: result.transfers)
            if let (_, error) = result.failed.first { showError("Move to Trash Failed", error: error) }
        }
    }

    /// Finder "Show View Options" (⌘J): toggles floating HUD panel.
    private func toggleViewOptions() {
        ViewOptionsService.shared.toggle(
            folderURL: activeTab.navigationHistory.currentURL,
            viewMode: activeTab.viewMode,
            iconSize: CGFloat(iconSize),
            fontSize: activeTab.viewMode == .list ? 13 : 11,
            groupBy: activeTab.directoryContents.groupBy,
            onStateChanged: {
                self.activeTab.viewMode = ViewOptionsService.shared.viewMode
                self.iconSize = Double(ViewOptionsService.shared.iconSize)
                self.activeTab.directoryContents.groupBy = ViewOptionsService.shared.groupBy
                self.persistViewState()
            },
            onUseAsDefaults: {
                UserDefaults.standard.set(Double(ViewOptionsService.shared.iconSize), forKey: Constants.defaultIconSizeKey)
                UserDefaults.standard.set(ViewOptionsService.shared.viewMode.rawValue, forKey: Constants.defaultViewModeKey)
            }
        )
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
                let newURL = try await FileOperationService.shared.renameItem(at: item.url, to: newName)
                await MainActor.run {
                    registerRenameUndo(originalURL: item.url, newURL: newURL)
                }
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
    private var activeUndoManager: UndoManager? {
        undoManager ?? NSApp.keyWindow?.undoManager
    }

    /// Restore successful transfers to their exact original paths, including names.
    private func registerRestoreUndo(name: String, transfers: [FileOperationResult.Transfer]) {
        guard let activeUndoManager, !transfers.isEmpty else { return }
        activeUndoManager.registerUndo(withTarget: UndoBox {
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
        activeUndoManager.setActionName(name)
    }

    /// Deletes items on undo (used for undoing copy, duplicate, or new folder creation).
    private func registerDeleteUndo(name: String, urls: [URL]) {
        guard let activeUndoManager, !urls.isEmpty else { return }
        activeUndoManager.registerUndo(withTarget: UndoBox {
            Task {
                _ = await FileOperationService.shared.deleteItems(urls)
                for pane in activePanes {
                    pane.directoryContents.reload()
                }
            }
        }) { box in
            box.work()
        }
        activeUndoManager.setActionName(name)
    }

    /// Reverses a rename operation.
    private func registerRenameUndo(originalURL: URL, newURL: URL) {
        guard let activeUndoManager else { return }
        activeUndoManager.registerUndo(withTarget: UndoBox {
            Task {
                _ = try? await FileOperationService.shared.renameItem(at: newURL, to: originalURL.lastPathComponent)
                for pane in activePanes {
                    pane.directoryContents.reload()
                }
            }
        }) { box in
            box.work()
        }
        activeUndoManager.setActionName("Rename")
    }

    /// Reverses a "New Folder with Selection" operation.
    private func registerNewFolderWithSelectionUndo(folderURL: URL, originalTransfers: [FileOperationResult.Transfer]) {
        guard let activeUndoManager else { return }
        activeUndoManager.registerUndo(withTarget: UndoBox {
            Task {
                _ = await FileOperationService.shared.restoreItems(originalTransfers)
                try? FileManager.default.removeItem(at: folderURL)
                for pane in activePanes {
                    pane.directoryContents.reload()
                }
            }
        }) { box in
            box.work()
        }
        activeUndoManager.setActionName("New Folder with Selection")
    }

    /// Consumes a pending URL queued for this window (restored tab on launch,
    /// or Cmd+T "new tab here"), if any.
    private func restoreIfPending() {
        guard let url = TabRestoreQueue.shared.pop() else { return }
        navigate(to: url)
    }

    private var statusBarInfo: some View {
        let items = activeTab.directoryContents.items
        let count = items.count
        let selectedCount = activeTab.selectionModel.selectedIDs.count

        let availableSpaceString: String = {
            let currentURL = activeTab.navigationHistory.currentURL
            if let values = try? currentURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]) {
                let bytes: Int64 = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
                if bytes > 0 {
                    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + " available"
                }
            }
            return ""
        }()

        let selectedSizeString: String = {
            guard selectedCount > 0 else { return "" }
            let selected = selectedItems
            let totalBytes = selected.compactMap(\.size).reduce(0, +)
            if totalBytes > 0 {
                return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            }
            return ""
        }()

        return HStack(spacing: 6) {
            if isSearchActive || !searchText.isEmpty || !searchCriteria.isEmpty {
                Text("Search: \(count) item\(count == 1 ? "" : "s")")
            } else if selectedCount > 0 {
                if !selectedSizeString.isEmpty {
                    Text("\(selectedCount) of \(count) selected (\(selectedSizeString))")
                } else {
                    Text("\(selectedCount) of \(count) selected")
                }
            } else {
                Text("\(count) item\(count == 1 ? "" : "s")")
            }
            if !availableSpaceString.isEmpty {
                Text("•")
                    .foregroundStyle(.tertiary)
                Text(availableSpaceString)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var bottomBarView: some View {
        if showPathBar {
            Divider()
            HStack(spacing: 8) {
                PathBarView(currentURL: activeTab.navigationHistory.currentURL) { url in
                    navigate(to: url)
                } onAddFavorite: { url in
                    sidebarModel.addFavorite(url: url)
                }
                Spacer()
                statusBarGitBranchView
                statusBarInfo
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    private var currentBrowserActions: BrowserActions {
        BrowserActions(
            copySelection: copySelectionToPasteboard,
            paste: { pasteFromPasteboard(move: false) },
            moveHere: { pasteFromPasteboard(move: true) },
            trashSelection: trashSelection,
            renameSelection: renameSelection,
            batchRenameSelection: batchRenameSelection,
            newFolder: newFolder,
            newFolderWithSelection: newFolderWithSelection,
            duplicateSelection: duplicateSelection,
            makeAlias: makeAliasSelection,
            showOriginal: showOriginalSelection,
            undo: { activeUndoManager?.undo() },
            redo: { activeUndoManager?.redo() },
            getInfo: getInfo,
            quickLook: { quickLook() },
            goBack: goBack,
            goForward: goForward,
            goToEnclosingFolder: {
                navigate(to: activeTab.navigationHistory.currentURL.deletingLastPathComponent())
            },
            navigateTo: navigate(to:),
            promptGoToFolder: { showGoToFolderSheet = true },
            promptConnectToServer: { showConnectToServerSheet = true },
            setViewMode: setViewMode,
            toggleHiddenFiles: toggleHiddenFiles,
            setGroupBy: { criterion in
                activeTab.directoryContents.groupBy = criterion
                persistViewState()
            },
            showViewOptions: toggleViewOptions,
            putBack: putBackSelection,
            setSplitLayout: setSplitLayout,
            toggleDualPane: toggleDualPane,
            cycleNextPane: cycleNextPane,
            togglePathBar: { showPathBar.toggle() },
            toggleSidebar: toggleSidebar,
            toggleTreePanel: {
                if showRightSidebar && rightSidebarTab == .tree {
                    showRightSidebar = false
                } else {
                    rightSidebarTab = .tree
                    showRightSidebar = true
                }
            },
            toggleInspector: { showRightSidebar.toggle() },
            showInspectorTab: { tab in
                rightSidebarTab = tab
                showRightSidebar = true
            },
            duplicateTab: duplicateTab,
            closeOtherTabs: closeOtherTabs,
            closeTabsToTheRight: closeTabsToTheRight,
            moveTabToNewWindow: moveTabToNewWindow,
            mergeAllWindows: mergeAllWindows,
            copyToInactivePane: copyToInactivePane,
            moveToInactivePane: moveToInactivePane,
            toggleSyncNavigation: toggleSyncNavigation,
            toggleFilterBar: toggleFilterBar,
            toggleTag: toggleColorTagOnSelection,
            clearTags: clearTagsOnSelection,
            downloadCloudSelection: downloadCloudSelection,
            evictCloudSelection: evictCloudSelection,
            copySHA256Checksum: copySHA256ChecksumForSelection,
            findDuplicatesInFolder: findDuplicatesInCurrentFolder,
            gitDiffSelection: diffSelection,
            gitStageSelection: stageSelection,
            gitUnstageSelection: unstageSelection,
            gitDiscardSelection: discardSelection,
            gitCommit: { showGitCommitSheet = true },
            gitSwitchBranch: { branch in switchGitBranch(to: branch) },
            gitCreateBranch: promptCreateGitBranch
        )
    }

    @ViewBuilder
    private var statusBarGitBranchView: some View {
        let currentURL = activeTab.navigationHistory.currentURL
        if GitService.shared.isGitRepository(at: currentURL) {
            let branch = GitService.shared.currentBranch(at: currentURL) ?? "HEAD"
            let isDirty = GitService.shared.isDirty(at: currentURL)
            let branches = GitService.shared.localBranches(at: currentURL)

            Menu {
                Section("Branch") {
                    ForEach(branches, id: \.self) { name in
                        Button {
                            switchGitBranch(to: name)
                        } label: {
                            if name == branch {
                                Label(name, systemImage: "checkmark")
                            } else {
                                Text(name)
                            }
                        }
                    }
                    Button("New Branch…") {
                        promptCreateGitBranch()
                    }
                }

                Section("Repository") {
                    Button("Commit Changes…") {
                        showGitCommitSheet = true
                    }
                    Button("View Diff…") {
                        diffSelection()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .imageScale(.small)
                    Text(branch)
                        .font(.caption)
                        .fontWeight(.medium)
                    if isDirty {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                    }
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Git Branch: \(branch)\(isDirty ? " (Uncommitted Changes)" : "")")

            Text("•")
                .foregroundStyle(.tertiary)
        }
    }

    private func diffSelection() {
        let currentURL = activeTab.navigationHistory.currentURL
        guard GitService.shared.isGitRepository(at: currentURL) else { return }
        let selected = selectedItems
        if let first = selected.first {
            gitDiffTargetURL = first.url
            showGitDiffSheet = true
        } else {
            let statusMap = GitService.shared.statusMap(forDirectory: currentURL)
            if let firstPath = statusMap.keys.first {
                gitDiffTargetURL = currentURL.appendingPathComponent(firstPath)
                showGitDiffSheet = true
            } else {
                gitDiffTargetURL = currentURL
                showGitDiffSheet = true
            }
        }
    }

    private func stageSelection() {
        let currentURL = activeTab.navigationHistory.currentURL
        guard GitService.shared.isGitRepository(at: currentURL) else { return }
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        Task {
            do {
                try await GitService.shared.stage(urls: urls, at: currentURL)
                await MainActor.run {
                    activeTab.directoryContents.reload()
                }
            } catch {
                await MainActor.run {
                    _ = NSAlert(error: error).runModal()
                }
            }
        }
    }

    private func unstageSelection() {
        let currentURL = activeTab.navigationHistory.currentURL
        guard GitService.shared.isGitRepository(at: currentURL) else { return }
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        Task {
            do {
                try await GitService.shared.unstage(urls: urls, at: currentURL)
                await MainActor.run {
                    activeTab.directoryContents.reload()
                }
            } catch {
                await MainActor.run {
                    _ = NSAlert(error: error).runModal()
                }
            }
        }
    }

    private func discardSelection() {
        let currentURL = activeTab.navigationHistory.currentURL
        guard GitService.shared.isGitRepository(at: currentURL) else { return }
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Discard Changes?"
        alert.informativeText = "Are you sure you want to discard changes in the selected \(urls.count == 1 ? "file" : "\(urls.count) files")? This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            try? await GitService.shared.discardChanges(for: urls, at: currentURL)
            await MainActor.run {
                activeTab.directoryContents.reload()
            }
        }
    }

    private func switchGitBranch(to branch: String) {
        let currentURL = activeTab.navigationHistory.currentURL
        Task {
            do {
                try await GitService.shared.switchBranch(to: branch, at: currentURL)
                await MainActor.run {
                    activeTab.directoryContents.reload()
                }
            } catch {
                await MainActor.run {
                    _ = NSAlert(error: error).runModal()
                }
            }
        }
    }

    private func promptCreateGitBranch() {
        let alert = NSAlert()
        alert.messageText = "Create New Branch"
        alert.informativeText = "Enter the name for the new Git branch:"
        alert.alertStyle = .informational
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.placeholderString = "branch-name"
        alert.accessoryView = input
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let currentURL = activeTab.navigationHistory.currentURL
            Task {
                do {
                    try await GitService.shared.createBranch(named: name, at: currentURL)
                    await MainActor.run {
                        activeTab.directoryContents.reload()
                    }
                } catch {
                    await MainActor.run {
                        _ = NSAlert(error: error).runModal()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sidebarContentView: some View {
        SidebarView(
            model: sidebarModel,
            selectedURL: activeTab.navigationHistory.currentURL,
            onNavigate: { url in
                navigate(to: url)
            },
            onFavoriteAdded: { _ in
            },
            onPerformCopy: { sources, destination in
                runFileOperation("Copying Files") { progress in
                    await FileOperationService.shared.copyItems(sources, to: destination, progress: progress)
                }
            },
            onPerformMove: { sources, destination in
                runFileOperation("Moving Files") { progress in
                    await FileOperationService.shared.moveItems(sources, to: destination, progress: progress)
                } onCompletion: { result in
                    registerRestoreUndo(name: "Move", transfers: result.transfers)
                }
            },
            onTagSelected: { tag in
                filterByTagFromSidebar(tag)
            }
        )
        .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 260)
    }

    @ViewBuilder
    private var detailContentView: some View {
        VStack(spacing: 0) {
            if showPermissionBanner && !dismissedFullDiskBanner {
                permissionBanner
            }
            if isSearchActive || !searchText.isEmpty || !searchCriteria.isEmpty {
                ScopeBarView(
                    currentFolderURL: activeTab.navigationHistory.currentURL,
                    resultCount: activeTab.directoryContents.items.count,
                    isGathering: SearchService.shared.isGathering,
                    scope: $searchScope,
                    filter: $searchFilter,
                    criteria: $searchCriteria,
                    onCriteriaChanged: {
                        performSearch(searchText)
                    },
                    onSaveSmartFolder: { name in
                        saveCurrentSearchAsSmartFolder(name: name)
                    },
                    onDismissSearch: {
                        dismissSearch()
                    }
                )
            }
            if showFilterBar {
                FilterBarView(directoryContents: activeTab.directoryContents) {
                    showFilterBar = false
                }
            }
            splitLayoutView

            bottomBarView
        }
        .navigationTitle(windowTitle)
        .toolbar {
            mainToolbarContent
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search")
    }

    @ViewBuilder
    private var inspectorContentView: some View {
        RightSidebarView(
            selectedTab: $rightSidebarTab,
            stagedURLs: $stagedURLs,
            sidebarModel: sidebarModel,
            selectedItems: selectedItems,
            currentFolderURL: activeTab.navigationHistory.currentURL,
            currentFolderItemCount: activeTab.directoryContents.items.count,
            onNavigate: { url in navigate(to: url) },
            onQuickLook: { quickLook() },
            onOpenTerminal: { url in
                Task {
                    try? await TerminalService.shared.openTerminal(
                        at: url,
                        emulator: TerminalService.shared.defaultTerminal()
                    )
                }
            },
            onReloadDirectory: {
                for pane in activePanes { pane.directoryContents.reload() }
            },
            onPerformCopy: { sources, destination in
                runFileOperation("Copying Files") { progress in
                    await FileOperationService.shared.copyItems(sources, to: destination, progress: progress)
                }
            },
            onPerformMove: { sources, destination in
                runFileOperation("Moving Files") { progress in
                    await FileOperationService.shared.moveItems(sources, to: destination, progress: progress)
                } onCompletion: { result in
                    registerRestoreUndo(name: "Move", transfers: result.transfers)
                }
            }
        )
        .inspectorColumnWidth(min: 240, ideal: 290, max: 440)
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

    private var windowTitle: String {
        let currentURL = activeTab.navigationHistory.currentURL
        return currentURL.path == FileManager.default.homeURL.path
            ? "Home"
            : (currentURL.lastPathComponent.isEmpty ? "Macintosh HD" : currentURL.lastPathComponent)
    }

    private func updateWindowTitle(for window: NSWindow? = nil) {
        guard let win = window ?? NSApp.keyWindow else { return }
        let currentURL = activeTab.navigationHistory.currentURL
        win.title = windowTitle
        win.representedURL = currentURL
    }

    /// Persistent banner shown while Full Disk Access is missing (Prompt 15).
    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Nautica has limited disk access. Cloud storage (OneDrive, Google Drive, Dropbox) and system folders may require Full Disk Access.")
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

/// Pure SwiftUI horizontal split container that does not introduce AppKit
/// NSTrackingSeparatorToolbarItem into the window titlebar.
private struct HorizontalSplit<Left: View, Right: View>: View {
    @State private var splitFraction: CGFloat = 0.5
    @GestureState private var dragOffset: CGFloat = 0
    let left: Left
    let right: Right

    init(@ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right) {
        self.left = left()
        self.right = right()
    }

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let minWidth: CGFloat = 160
            let dividerWidth: CGFloat = 1
            let availableWidth = max(0, totalWidth - dividerWidth)
            let baseLeftWidth = availableWidth * splitFraction
            let leftWidth = min(max(minWidth, baseLeftWidth + dragOffset), max(minWidth, availableWidth - minWidth))

            HStack(spacing: 0) {
                left
                    .frame(width: leftWidth)

                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(width: dividerWidth)
                    .overlay(
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 9)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture()
                                    .updating($dragOffset) { value, state, _ in
                                        state = value.translation.width
                                    }
                                    .onEnded { value in
                                        let finalWidth = min(max(minWidth, baseLeftWidth + value.translation.width), max(minWidth, availableWidth - minWidth))
                                        if availableWidth > 0 {
                                            splitFraction = finalWidth / availableWidth
                                        }
                                    }
                            )
                    )
                    .onHover { inside in
                        if inside {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }

                right
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Pure SwiftUI vertical split container that does not introduce AppKit
/// NSTrackingSeparatorToolbarItem into the window titlebar.
private struct VerticalSplit<Top: View, Bottom: View>: View {
    @State private var splitFraction: CGFloat = 0.5
    @GestureState private var dragOffset: CGFloat = 0
    let top: Top
    let bottom: Bottom

    init(@ViewBuilder top: () -> Top, @ViewBuilder bottom: () -> Bottom) {
        self.top = top()
        self.bottom = bottom()
    }

    var body: some View {
        GeometryReader { geo in
            let totalHeight = geo.size.height
            let minHeight: CGFloat = 120
            let dividerHeight: CGFloat = 1
            let availableHeight = max(0, totalHeight - dividerHeight)
            let baseTopHeight = availableHeight * splitFraction
            let topHeight = min(max(minHeight, baseTopHeight + dragOffset), max(minHeight, availableHeight - minHeight))

            VStack(spacing: 0) {
                top
                    .frame(height: topHeight)

                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(height: dividerHeight)
                    .overlay(
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: 9)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture()
                                    .updating($dragOffset) { value, state, _ in
                                        state = value.translation.height
                                    }
                                    .onEnded { value in
                                        let finalHeight = min(max(minHeight, baseTopHeight + value.translation.height), max(minHeight, availableHeight - minHeight))
                                        if availableHeight > 0 {
                                            splitFraction = finalHeight / availableHeight
                                        }
                                    }
                            )
                    )
                    .onHover { inside in
                        if inside {
                            NSCursor.resizeUpDown.push()
                        } else {
                            NSCursor.pop()
                        }
                    }

                bottom
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

/// Data container for presenting the conflict resolution modal sheet.
private struct ConflictSheetData: Identifiable {
    let id = UUID()
    let sources: [URL]
    let model: ConflictResolutionModel
}

/// Configures the hosting NSWindow once it exists (one-time idempotent pass).
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView) }
    }

    private func configure(_ view: NSView) {
        guard let window = view.window else { return }
        onWindow(window)
    }
}

private extension View {
    @ViewBuilder
    func gitSheets(
        showDiff: Binding<Bool>,
        showCommit: Binding<Bool>,
        targetURL: URL?,
        repoURL: URL,
        onReload: @escaping () -> Void
    ) -> some View {
        self
            .sheet(isPresented: showDiff) {
                if let targetURL {
                    GitDiffSheet(
                        targetURL: targetURL,
                        repositoryRoot: repoURL,
                        onRefreshNeeded: onReload
                    )
                }
            }
            .sheet(isPresented: showCommit) {
                GitCommitSheet(
                    repositoryRoot: repoURL,
                    onCommitCompleted: onReload
                )
            }
    }

    @ViewBuilder
    func toolSheets(
        showCompressPassword: Binding<Bool>,
        compressPasswordCount: Int,
        onCompressPassword: @escaping (String) -> Void,
        showDuplicateFinder: Binding<Bool>,
        duplicateFinderDirectory: URL,
        onTrashDuplicates: @escaping ([URL]) -> Void
    ) -> some View {
        self
            .sheet(isPresented: showCompressPassword) {
                CompressPasswordSheet(itemCount: compressPasswordCount) { password in
                    onCompressPassword(password)
                }
            }
            .sheet(isPresented: showDuplicateFinder) {
                DuplicateFinderSheet(
                    targetDirectory: duplicateFinderDirectory,
                    onTrashFiles: { urls in
                        onTrashDuplicates(urls)
                    }
                )
            }
    }
}

#Preview {
    BrowserView()
}
