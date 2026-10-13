# Nautica — Kimi Code Prompts

> **Instructions for Kimi Code**: These prompts are designed to be fed sequentially to a coding agent (Kimi Code) to implement the Nautica file manager. Each prompt is self-contained and builds on the previous work. Do not skip prompts; each one establishes files and patterns that subsequent prompts depend on.
>
> **Tech Stack**: macOS 14+, Swift 5.9+, SwiftUI for chrome/toolbars, AppKit (`NSCollectionView`/`NSTableView`) for file listings, SwiftData for view state/preferences, SQLite (GRDB.swift) for tags, Combine for reactive state.
> **License**: GPL-2.0 or later (same as Nemo).
> **Reference**: `Nautica-PRD-v1.0.md` in the same directory.

---

## Prompt 0: Project Scaffold & Architecture

Create a new macOS Xcode project called **Nautica** (bundle ID: `com.arthur.nautica`) with the following target structure:

- **Target**: macOS App, SwiftUI interface, no Core Data template, no tests yet.
- **Minimum deployment**: macOS 14.0 (Sonoma).
- **Package dependencies** (via Swift Package Manager):
  - `GRDB.swift` (https://github.com/groue/GRDB.swift) — for SQLite tag storage.
- **Project structure** (group folders in Xcode matching disk structure):
  ```
  Nautica/
  ├── NauticaApp.swift              # App entry point, @main
  ├── Info.plist                    # CFBundleDocumentTypes for folder opening
  ├── Models/
  │   ├── FileItem.swift            # Representation of a file/folder in the FS
  │   ├── DirectoryContents.swift   # Observable container for directory listing
  │   ├── SelectionModel.swift      # Tracks selected items (multi-select with Cmd/Shift)
  │   └── ViewState.swift           # SwiftData model for per-folder view persistence
  ├── Services/
  │   ├── FileSystemService.swift   # File listing, metadata, NSFileCoordinator wrappers
  │   ├── ThumbnailService.swift    # QLThumbnailGenerator async wrapper
  │   ├── TagService.swift          # GRDB-backed tag CRUD
  │   └── TerminalService.swift     # Opens current dir in Terminal/iTerm (stub for now)
  ├── Views/
  │   ├── BrowserView.swift         # Main window content: sidebar + file view
  │   ├── SidebarView.swift         # SwiftUI sidebar with Favorites, Tree, Tags
  │   ├── FileViews/
  │   │   ├── IconView.swift        # AppKit NSCollectionView wrapper for icon grid
  │   │   ├── ListView.swift        # AppKit NSTableView wrapper for list/table
  │   │   └── FileViewCoordinator.swift  # Hosts icon or list view, handles selection
  │   ├── Chrome/
  │   │   ├── PathBarView.swift     # Breadcrumb toolbar view
  │   │   └── ToolbarView.swift     # NSToolbar items (back/forward/view mode/hidden files)
  │   └── Windows/
  │       └── MainWindow.swift      # NSWindowRepresentable or NSWindowController wrapper
  └── Utilities/
      ├── Extensions/
      │   ├── URL+FileOperations.swift
      │   └── FileManager+Helpers.swift
      └── Constants.swift           # App constants, notification names, UserDefaults keys
  ```

**Requirements:**
- Set up the `NauticaApp.swift` with a `WindowGroup` that creates a `MainWindow`.
- Add the `GRDB` package dependency.
- Configure `Info.plist` so Nautica can open folders (UTType: `public.folder`).
- Add necessary entitlements: `com.apple.security.files.user-selected.read-write` and `com.apple.security.files.all` (for full disk access, non-App Store).
- Add a `Constants.swift` with `static let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Nautica")`.
- Build must compile with zero errors (all stubs can be empty `struct`/`class` with no-op bodies).
- Add a `README.md` at the project root explaining the architecture and how to build.

**Do NOT implement** any view logic yet — just the skeleton, imports, and protocol conformances.

---

## Prompt 1: File System Models & Directory Enumeration

Implement the data models and file system service for browsing directories.

**Files to create/modify:**

### `Models/FileItem.swift`
```swift
struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let modificationDate: Date?
    let creationDate: Date?
    let isHidden: Bool
    let kind: String  // UTType.localizedDescription or fallback
}
```
- Add a computed property `iconImage: NSImage?` that returns a lazy-loaded icon.

### `Models/DirectoryContents.swift`
```swift
@Observable
class DirectoryContents {
    var url: URL
    var items: [FileItem] = []
    var isLoading: Bool = false
    var sortDescriptor: SortDescriptor<FileItem>
    var showHiddenFiles: Bool = false
    
    func reload()
    func sort(by: KeyPath<FileItem, some Comparable>)
}
```
- `reload()` must enumerate the directory using `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:)`.
- Filter out hidden files unless `showHiddenFiles` is true.
- Sort by name ascending by default.
- Must use `NSFileCoordinator` for reading directory contents.

### `Services/FileSystemService.swift`
```swift
actor FileSystemService {
    static let shared = FileSystemService()
    
    func contentsOfDirectory(at url: URL, includingHidden: Bool) async throws -> [FileItem]
    func attributesOfItem(at url: URL) -> FileItem?
    func fileExists(at url: URL) -> Bool
}
```
- The `contentsOfDirectory` method should:
  1. Use `NSFileCoordinator.coordinate(readingItemAt:options:)`
  2. Fetch `URLResourceKey` values: `.nameKey`, `.isDirectoryKey`, `.fileSizeKey`, `.contentModificationDateKey`, `.creationDateKey`, `.isHiddenKey`, `.contentTypeKey`
  3. Return sorted `[FileItem]`
- Handle permission errors gracefully — if a directory is unreadable, return an empty array and set an error property.

### `Utilities/Extensions/FileManager+Helpers.swift`
- Add helpers: `desktopURL`, `homeURL`, `downloadsURL` that return standard directory URLs.
- Add `isHiddenFile(at:)` that checks if a file starts with `.` or has the `isHidden` resource key.

**Acceptance criteria:**
- `DirectoryContents.reload()` can enumerate `/Users/<user>` and display ~30 items in under 100ms.
- Hidden files are excluded by default.
- Sorting by name works A→Z, insensitive to case.
- The code compiles with no warnings (enable `-Wall -Wextra` equivalent in Xcode build settings).

---

## Prompt 2: Selection Model & Keyboard Navigation

Implement the selection model that tracks which files are selected and handles keyboard/mouse interactions.

**Files to create/modify:**

### `Models/SelectionModel.swift`
```swift
@Observable
class SelectionModel {
    var selectedIDs: Set<UUID> = []
    var anchorID: UUID?  // For Shift-range selection
    var lastClickedID: UUID?
    
    func select(_ id: UUID, modifierFlags: NSEvent.ModifierFlags)
    func selectRange(from: UUID, to: UUID, in items: [FileItem])
    func selectAll(in items: [FileItem])
    func deselectAll()
    func invertSelection(in items: [FileItem])
    func isSelected(_ id: UUID) -> Bool
}
```

**Selection behavior (exactly like Finder/Nemo):**
- **Plain click**: Select only clicked item, deselect all others. Set `lastClickedID` = clicked item.
- **Cmd-click**: Toggle clicked item in selection. Set `lastClickedID` = clicked item.
- **Shift-click**: Select range from `lastClickedID` (or `anchorID`) to clicked item. If no anchor, select from first item in list.
- **Cmd+A**: Select all items.
- **Cmd+Shift+A** or **Esc**: Deselect all.
- **Arrow keys (Up/Down/Left/Right)**: Move selection by one item in icon view (grid-aware) or list view. With Shift, extend selection.
- **Type-ahead**: If user types characters rapidly (within 500ms of each keystroke), jump to first item whose name starts with those characters. In list view, this also selects that item.

### `Views/FileViews/FileViewCoordinator.swift`
```swift
struct FileViewCoordinator: NSViewRepresentable {
    var directoryContents: DirectoryContents
    var selectionModel: SelectionModel
    var viewMode: ViewMode  // .icon or .list
    
    func makeNSView(context: Context) -> NSView
    func updateNSView(_ nsView: NSView, context: Context)
}
```
- This is a SwiftUI wrapper that hosts either the Icon view (NSCollectionView) or List view (NSTableView).
- It forwards selection events from AppKit to the `SelectionModel`.
- It handles key events via `keyDown(with:)` forwarded from the hosted NSView.

**Requirements:**
- `SelectionModel` must be `@Observable` (Swift 5.9 Observation framework) so SwiftUI views auto-update.
- Selection state must be testable: write a simple XCTest in `NauticaTests/SelectionModelTests.swift` that verifies Cmd-click toggle and Shift-click range.

**Acceptance criteria:**
- Clicking an item selects it; clicking another deselects the first.
- Cmd-click adds/removes items from selection.
- Shift-click selects a contiguous range.
- Arrow keys navigate selection without crashing.
- Unit tests pass.

---

## Prompt 3: Icon View (NSCollectionView)

Implement the icon grid view using AppKit's `NSCollectionView` wrapped for SwiftUI.

**Files to create/modify:**

### `Views/FileViews/IconView.swift`
Create an `NSCollectionView`-based grid that:
- Uses `NSCollectionViewFlowLayout` with adaptive column count (minimum item width 100pt, spacing 10pt).
- Each cell displays:
  - File/folder icon (`NSWorkspace.shared.icon(forFile:)`) at configurable size (default 64pt, adjustable 32–256pt via slider in toolbar).
  - Filename below the icon, truncated with ellipsis if too long.
  - Selection highlight: a rounded rect with `NSColor.selectedContentBackgroundColor` fill and a subtle border.
- Supports drag-and-drop:
  - Drag selected items out to other apps (promised file URLs).
  - Accept drops from Finder/other Nautica windows (copy or move based on modifier key).
- Double-click opens the item (folders navigate, files open with `NSWorkspace.shared.open()`).
- Space bar triggers Quick Look (delegated to a coordinator).

### `Views/FileViews/IconViewCell.swift`
```swift
class IconViewItem: NSCollectionViewItem {
    var iconView: NSImageView!
    var nameLabel: NSTextField!
    var fileItem: FileItem?
    
    func configure(with item: FileItem, isSelected: Bool)
}
```
- Override `setSelected(_:)` to update the selection background.

### Key behaviors:
- **Right-click**: Shows context menu with Open, Get Info, Rename, Move to Trash, Tags (stub), and Share (via `NSSharingService`).
- **Context menu "Open With"**: Dynamically populated from `NSWorkspace.shared.urlsForApplications(toOpen:)`.
- **Empty area click**: Deselects all.

**Performance requirements:**
- Use `NSCollectionViewDiffableDataSource` with `NSDiffableDataSourceSnapshot` for efficient updates.
- Icon images must be loaded lazily (off-main thread) and cached in `NSCache<NSURL, NSImage>`.
- For directories with >1000 items, load icons in batches of 50 using `OperationQueue` with QoS `.userInitiated`.

**Acceptance criteria:**
- Displays `/Applications` (~200 items) with icons in under 500ms.
- Scrolling through 5000 items stays at 60fps (test with Instruments).
- Selection highlight updates immediately on click.
- Dragging 10 files to Desktop copies them (uses `NSFileCoordinator`).

---

## Prompt 4: List View (NSTableView)

Implement the list/table view using AppKit's `NSTableView` wrapped for SwiftUI.

**Files to create/modify:**

### `Views/FileViews/ListView.swift`
Create an `NSTableView`-based list with these columns:
- **Name** (string): File/folder name with a small icon leading.
- **Size** (int64): Human-readable size (B, KB, MB, GB) using `ByteCountFormatter`.
- **Modified** (date): Relative date if recent, absolute otherwise (`DateFormatter`).
- **Created** (date): Same formatting as Modified.
- **Kind** (string): UTType localized description.
- **Tags** (string): Comma-separated tag names (stub, reads from TagService later).

**Features:**
- Click column header to sort ascending; click again to sort descending. Show a sort indicator arrow.
- Drag column headers to reorder columns.
- Resize columns by dragging dividers.
- Column widths and order persisted via SwiftData (F-014, stub the persistence for now, just store in UserDefaults).
- Type-ahead selection: typing while focused jumps to matching filename (case-insensitive, starts-with match).
- Full keyboard navigation: arrows, Home/End, Page Up/Down.

### `Views/FileViews/ListViewCell.swift`
```swift
class ListViewCell: NSTableCellView {
    func configure(with item: FileItem, forColumn: TableColumn)
}
```
- Use `NSTableView.DataSource` + `NSTableView.Delegate` or `NSDiffableDataSourceSnapshot` if feasible.
- For the Name column, use an `NSImageView` + `NSTextField` embedded in the cell view.

### Sorting:
```swift
enum SortKey: String, CaseIterable {
    case name, size, modificationDate, creationDate, kind
}
```
- Sorting must happen in `DirectoryContents` so that both Icon and List views share the same sort order.

**Acceptance criteria:**
- List view displays `/usr/bin` (~200 items) sorted by name in < 200ms.
- Sorting by Size descending shows largest files first.
- Column drag reorder works and persists across app restarts (via UserDefaults for now).
- Type-ahead "cal" jumps to Calculator.app in `/Applications`.

---

## Prompt 5: Sidebar (Favorites, Tree, Tags)

Implement the sidebar using pure SwiftUI.

**Files to create/modify:**

### `Views/SidebarView.swift`
```swift
struct SidebarView: View {
    @State var favorites: [SidebarItem] = []
    @State var treeRoot: SidebarItem?  // Home directory tree
    @State var tags: [TagItem] = []    // From TagService (stub)
    
    var onNavigate: (URL) -> Void
    var onFavoriteAdded: (URL) -> Void
}
```

**Sections (in order):**
1. **Favorites** — User-configured list of URLs. Default favorites: Home, Desktop, Documents, Downloads, Pictures, Projects (if exists). Each item shows a folder icon + name. Draggable to reorder. Right-click to remove.
2. **Tree** — Expandable tree starting at the user's home directory. Uses lazy loading: only children of expanded nodes are enumerated. Show a spinner while loading. Depth limit: no hard limit, but cap at 3 levels initially expanded.
3. **Tags** — Placeholder section for now; reads from `TagService` and shows colored circles + tag names.
4. **Recent** — Last 10 navigated directories (persisted in UserDefaults).

### `Models/SidebarItem.swift`
```swift
struct SidebarItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let icon: NSImage?
    var children: [SidebarItem]?
    var isExpanded: Bool = false
}
```

**Interactions:**
- Click a favorite/tree item → call `onNavigate(url)`.
- Drag a folder from the main view onto the Favorites section → add it as a favorite.
- Reorder favorites via drag-and-drop (update `UserDefaults` order).
- Disclosure triangles for tree nodes (SwiftUI `List` with `children:` or custom `OutlineGroup`).

**Persistence:**
- Favorites list stored in `UserDefaults` as array of bookmark data (`URL.bookmarkData()`).
- Recent list stored in `UserDefaults` as array of path strings.

**Acceptance criteria:**
- Sidebar shows default favorites on first launch.
- Clicking Desktop navigates the main view to Desktop.
- Expanding Tree → Home shows immediate subdirectories.
- Dragging a folder from Finder to Favorites adds it.

---

## Prompt 6: Path Bar (Breadcrumb)

Implement the breadcrumb path bar in the toolbar.

**Files to create/modify:**

### `Views/Chrome/PathBarView.swift`
```swift
struct PathBarView: View {
    var currentURL: URL
    var onNavigate: (URL) -> Void
    var onAddFavorite: (URL) -> Void
    
    var body: some View {
        // Horizontal stack of clickable path segments
    }
}
```

**Visual design:**
- Each segment is a button with the folder name.
- Separators between segments: a small `>` chevron (`NSImage(named: NSImage.goRightTemplateName)`), muted color.
- Root segment shows a small home icon (`NSImage(named: NSImage.homeTemplateName)`) instead of "Users".
- Active segment (current directory) is bold or slightly highlighted.

**Interactions:**
- Click a segment → navigate to that directory.
- Right-click a segment → context menu showing:
  - All sibling folders at that level (e.g., right-clicking "Projects" shows Documents, Downloads, Desktop, etc. as a submenu).
  - "Open in New Tab"
  - "Add to Favorites"
- Drag a segment to the sidebar → add as favorite.
- The bar is scrollable horizontally if the path is too long (wrap in `ScrollView(.horizontal, showsIndicators: false)`).

**Requirements:**
- Extract path components from `currentURL.pathComponents`.
- Reconstruct the URL for each segment by joining components up to that index.
- Use `FileManager` to list siblings for the right-click menu.

**Acceptance criteria:**
- Navigating to `/Users/arthur/Projects/Nautica` shows: 🏠 > arthur > Projects > Nautica.
- Clicking "Projects" navigates to `/Users/arthur/Projects`.
- Right-clicking "Projects" shows sibling folders (Desktop, Documents, Downloads, etc.).

---

## Prompt 7: Toolbar & View Mode Switching

Implement the main window toolbar with view controls and navigation buttons.

**Files to create/modify:**

### `Views/Chrome/ToolbarView.swift`
Use `NSToolbar` (not SwiftUI Toolbar) because we need fine-grained control. Create a custom `NSToolbarDelegate`:

```swift
class BrowserToolbar: NSToolbar, NSToolbarDelegate {
    var onBack: () -> Void
    var onForward: () -> Void
    var onViewModeChanged: (ViewMode) -> Void
    var onToggleHiddenFiles: () -> Void
    var onIconSizeChanged: (CGFloat) -> Void
}
```

**Toolbar items (left to right):**
1. **Back** (`NSToolbarItem`) — Navigate backward in history. Disabled if no back history.
2. **Forward** — Navigate forward in history. Disabled if no forward history.
3. **Path Bar** (custom `NSToolbarItem` with `PathBarView` as view) — Flexible space, takes remaining width.
4. **View Mode** (`NSSegmentedControl` with 2 segments: icon 🔲, list ☰) — Toggles between icon and list view.
5. **Icon Size Slider** (`NSSlider`, 32–256) — Only visible in icon view mode.
6. **Hidden Files Toggle** (`NSButton` with checkbox or toggle style) — Shows/hides dotfiles.

### `Views/Windows/MainWindow.swift`
```swift
struct MainWindow: Scene {
    var body: some Scene {
        WindowGroup {
            BrowserView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
    }
}
```
- The window must have a custom `NSToolbar` attached via `.toolbar { }` or by creating an `NSWindowController` in `AppDelegate`/`WindowDelegate`.
- Since we're using SwiftUI's `WindowGroup`, you may need to use `NSApp.windows.first?.toolbar = browserToolbar` in a `.onAppear` or via a `WindowDelegate`.

### Navigation History:
```swift
@Observable
class NavigationHistory {
    var backStack: [URL] = []
    var forwardStack: [URL] = []
    var currentURL: URL
    
    func navigate(to url: URL)
    func goBack() -> URL?
    func goForward() -> URL?
    func canGoBack -> Bool
    func canGoForward -> Bool
}
```
- `navigate(to:)` pushes current onto backStack, clears forwardStack, sets new current.
- Back/Forward buttons update `DirectoryContents.url`.

**Acceptance criteria:**
- Back button navigates to previous directory; Forward reverses.
- View mode toggle switches between icon and list instantly.
- Hidden files toggle shows/hides dotfiles in both views.
- Icon size slider changes icon view cell size in real time.

---

## Prompt 8: Tabs

Implement tabbed browsing within a single window.

**Files to create/modify:**

### `Models/TabState.swift`
```swift
@Observable
class TabState: Identifiable, Hashable {
    let id = UUID()
    var directoryContents: DirectoryContents
    var selectionModel: SelectionModel
    var navigationHistory: NavigationHistory
    var viewMode: ViewMode
    var title: String { directoryContents.url.lastPathComponent }
}
```

### `Views/Windows/MainWindow.swift`
- Support multiple `TabState` instances.
- Use SwiftUI's `TabView` or native macOS tabbing via `NSWindow.addTabbedWindow`.
- **Preferred approach**: Use `NSWindow`'s native tabbing (`NSWindow.tabbingMode = .preferred`) because it gives native macOS tab behavior. To make this work with SwiftUI:
  - Each tab is a separate `NSWindow` with the same `BrowserView` content.
  - Use `NSApp.mainWindow?.addTabbedWindow(newWindow, ordered: .above)` for Cmd+T.

**Keyboard shortcuts:**
- `Cmd+T` → New tab with same directory as current.
- `Cmd+W` → Close current tab (or window if last tab).
- `Cmd+Shift+]` / `[` → Next/Previous tab.
- `Cmd+1`–`Cmd+9` → Switch to tab N.

**Persistence on quit:**
- Before app terminates, save all open tabs' URLs to `UserDefaults` as an array of path strings.
- On launch, restore tabs from saved URLs (or open Home if none).

**Acceptance criteria:**
- Cmd+T opens a new tab.
- Tabs show the folder name as title.
- Closing a tab doesn't crash; closing the last tab closes the window.
- Tab state (directory, view mode) is independent per tab.
- On relaunch, previously open tabs are restored.

---

## Prompt 9: Quick Look Integration

Integrate macOS Quick Look for Space-bar preview.

**Files to create/modify:**

### `Services/QuickLookService.swift`
```swift
import QuickLook

class QuickLookService: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookService()
    var previewURLs: [URL] = []
    var currentIndex: Int = 0
    
    func showPreview(for urls: [URL], selectedIndex: Int)
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem!
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int
}
```

### Integration points:
- In `FileViewCoordinator` (and both IconView and ListView), handle `keyDown` for Space.
- If Space is pressed and items are selected, call `QuickLookService.shared.showPreview(for: selectedURLs, selectedIndex: 0)`.
- QLPreviewPanel should show the first selected item.
- While QL is open, Up/Down arrow keys should navigate to the previous/next file in the current view (close and reopen QL on the new file).

**Requirements:**
- Must conform to `QLPreviewPanelDataSource` and `QLPreviewPanelDelegate`.
- The panel must become key and first responder.
- Handle `QLPreviewPanel.shared()` correctly — only one panel exists globally.

**Acceptance criteria:**
- Pressing Space on a selected file opens Quick Look within 100ms.
- Pressing Down while QL is open moves to the next file and updates the preview.
- Pressing Escape or Space again closes QL.

---

## Prompt 10: File Operations (Copy, Move, Delete, Rename)

Implement the core file operations with progress UI.

**Files to create/modify:**

### `Services/FileOperationService.swift`
```swift
actor FileOperationService {
    static let shared = FileOperationService()
    
    func copyItems(_ urls: [URL], to destination: URL) async throws -> FileOperationResult
    func moveItems(_ urls: [URL], to destination: URL) async throws -> FileOperationResult
    func trashItems(_ urls: [URL]) async throws -> FileOperationResult
    func renameItem(at url: URL, to newName: String) async throws -> URL
}

struct FileOperationResult {
    let succeeded: [URL]
    let failed: [(URL, Error)]
}
```

**Requirements:**
- All operations use `NSFileCoordinator`.
- Copy/move operations:
  - If destination exists, auto-rename with "filename 1.ext", "filename 2.ext" pattern.
  - Report progress via `Progress` object.
- Trash:
  - Use `NSWorkspace.shared.recycle(_ urls)` which moves to Trash with sound.
  - Support Undo via `NSUndoManager` registered in the main window.
- Progress UI:
  - Show an `NSProgressIndicator` sheet or floating panel for operations > 1 second.
  - Display: operation name, current file name, overall progress bar, bytes transferred / total bytes, ETA.
  - Cancel button that cancels the operation (clean up partial copies).

### `Views/Chrome/ProgressPanel.swift`
```swift
struct ProgressPanel: View {
    @ObservedObject var progress: Progress
    var operationName: String
    var onCancel: () -> Void
}
```
- Presented as a sheet over the main window.

**Undo support:**
- After a move/trash operation, register an undo action with `NSUndoManager`:
  ```swift
  undoManager.registerUndo(withTarget: self) { target in
      // Move back from trash or restore to original location
  }
  ```
- Undo is available via Cmd+Z and Edit menu.

**Acceptance criteria:**
- Copying 100 files to Desktop shows progress and completes successfully.
- Canceling a copy at 50% leaves no partial files in destination.
- Moving a file to Trash can be undone with Cmd+Z (restores to original location).
- Renaming a file updates the view immediately.

---

## Prompt 11: SQLite Tag Service (GRDB)

Implement the tag storage and management using GRDB.swift.

**Files to create/modify:**

### `Models/TagItem.swift`
```swift
struct TagItem: Codable, FetchableRecord, MutablePersistableRecord {
    var id: UUID
    var name: String
    var colorHex: String  // e.g., "#FF5733"
    var createdAt: Date
}

struct FileTag: Codable, FetchableRecord, MutablePersistableRecord {
    var id: UUID
    var fileURL: String  // URL.absoluteString
    var tagID: UUID
    var appliedAt: Date
}
```

### `Services/TagService.swift`
```swift
actor TagService {
    static let shared = TagService()
    private var dbQueue: DatabaseQueue?
    
    func setupDatabase() throws
    func createTag(name: String, colorHex: String) async throws -> TagItem
    func deleteTag(id: UUID) async throws
    func applyTag(_ tagID: UUID, to url: URL) async throws
    func removeTag(_ tagID: UUID, from url: URL) async throws
    func tagsForFile(_ url: URL) async -> [TagItem]
    func filesWithTag(_ tagID: UUID) async -> [URL]
    func allTags() async -> [TagItem]
}
```

**Database schema:**
```sql
CREATE TABLE tag_item (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    colorHex TEXT NOT NULL,
    createdAt DATETIME NOT NULL
);

CREATE TABLE file_tag (
    id TEXT PRIMARY KEY,
    fileURL TEXT NOT NULL,
    tagID TEXT NOT NULL REFERENCES tag_item(id) ON DELETE CASCADE,
    appliedAt DATETIME NOT NULL,
    UNIQUE(fileURL, tagID)
);

CREATE INDEX idx_file_tag_url ON file_tag(fileURL);
CREATE INDEX idx_file_tag_tag ON file_tag(tagID);
```

**Database location:** `~/Library/Application Support/Nautica/Tags.sqlite`

**Requirements:**
- `setupDatabase()` creates the file and tables if they don't exist.
- All operations are `async` and run on the GRDB background queue.
- Deleting a tag cascades to remove all `file_tag` entries (via `ON DELETE CASCADE`).
- Thread-safe: use GRDB's `dbQueue.write { }` and `dbQueue.read { }`.

**Acceptance criteria:**
- Creating a tag "Red" with color `#FF0000` persists to SQLite.
- Applying "Red" to `/Users/arthur/file.txt` returns "Red" in `tagsForFile()`.
- Deleting "Red" removes it from all files.
- Database file is created on first launch if absent.

---

## Prompt 12: SwiftData View State Persistence

Implement per-folder view state persistence using SwiftData.

**Files to create/modify:**

### `Models/ViewState.swift`
```swift
import SwiftData

@Model
class FolderViewState {
    @Attribute(.unique) var folderPath: String
    var viewMode: String  // "icon" or "list"
    var iconSize: Double
    var sortKey: String   // "name", "size", "modificationDate", etc.
    var sortAscending: Bool
    var showHiddenFiles: Bool
    var columnWidths: [String: Double]?  // JSON-encoded for list view columns
    var columnOrder: [String]?           // Ordered column identifiers
    var lastVisited: Date
    
    init(folderPath: String, viewMode: String = "icon", iconSize: Double = 64, ...)
}
```

### `Services/ViewStateService.swift`
```swift
@Observable
class ViewStateService {
    private var context: ModelContext
    
    func state(for folderPath: String) -> FolderViewState
    func saveState(_ state: FolderViewState)
    func migrateFromUserDefaultsIfNeeded()  // One-time migration
}
```

**Requirements:**
- SwiftData container initialized in `NauticaApp.swift`:
  ```swift
  .modelContainer(for: FolderViewState.self)
  ```
- `state(for:)` returns existing state or creates a default one.
- When user changes view mode, icon size, sort, or hidden files toggle, update and save the state.
- States are saved automatically on change (debounced by 500ms).

**Integration:**
- `BrowserView` observes the current folder's `FolderViewState` and passes values to child views.
- On folder navigation, load the state and apply: switch view mode, set icon size, restore sort, etc.

**Acceptance criteria:**
- Setting `~/Photos` to icon view 128px persists after app restart.
- Returning to `~/Photos` restores icon view 128px.
- List view sort order (Size descending) persists per-folder.

---

## Prompt 13: Terminal Integration

Implement "Open in Terminal" functionality.

**Files to create/modify:**

### `Services/TerminalService.swift`
```swift
enum TerminalEmulator: String, CaseIterable, Identifiable {
    case terminal = "Terminal"
    case iTerm = "iTerm"
    case kitty = "Kitty"
    case warp = "Warp"
    
    var id: String { rawValue }
    var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iTerm: return "com.googlecode.iterm2"
        case .kitty: return "net.kovidgoyal.kitty"
        case .warp: return "dev.warp.Warp-Stable"
        }
    }
}

actor TerminalService {
    static let shared = TerminalService()
    
    func openTerminal(at url: URL, emulator: TerminalEmulator) async throws
    func detectInstalledTerminals() -> [TerminalEmulator]
    func defaultTerminal() -> TerminalEmulator
}
```

**Implementation:**
- Use `NSWorkspace.shared.openApplication(at:configuration:)` to open the terminal app.
- For Terminal.app: use AppleScript or `osascript` to create a new window at the path:
  ```applescript
  tell application "Terminal"
      do script "cd '\(url.path)'"
      activate
  end tell
  ```
- For iTerm2: use its AppleScript API or URL scheme.
- For Kitty: execute `/Applications/kitty.app/Contents/MacOS/kitty --directory <path>`.
- For Warp: use `open -a Warp <path>` or check their documented URL scheme.
- If the preferred terminal is not installed, fall back to Terminal.app.

**Settings:**
- Add a preference in Settings/Preferences window (`SettingsView.swift`) to choose default terminal from detected installed options.
- Default: auto-detect on first launch; if only Terminal.app exists, use that.

**Acceptance criteria:**
- Pressing Cmd+Shift+T opens the current directory in the selected terminal.
- If iTerm2 is installed and selected, it opens there instead of Terminal.app.
- The terminal window opens with the working directory already set.

---

## Prompt 14: Settings / Preferences Window

Implement a preferences window.

**Files to create/modify:**

### `Views/Settings/SettingsView.swift`
```swift
struct SettingsView: View {
    @AppStorage("defaultTerminal") var defaultTerminal: String = TerminalEmulator.terminal.rawValue
    @AppStorage("showPathBar") var showPathBar: Bool = true
    @AppStorage("confirmTrash") var confirmTrash: Bool = true
    @AppStorage("showExtensions") var showExtensions: Bool = true
    
    var body: some View {
        TabView {
            GeneralSettingsTab()
            AppearanceSettingsTab()
            TerminalSettingsTab()
            AdvancedSettingsTab()
        }
        .frame(width: 500, height: 400)
    }
}
```

**Tabs:**
1. **General**:
   - Default new window folder (Home / Desktop / Last visited)
   - Show extensions (always / never / for all except known)
   - Confirm before moving to trash (checkbox)
   - Show hidden files by default (checkbox)
2. **Appearance**:
   - Default view mode (Icon / List)
   - Default icon size slider
   - Sidebar width (slider)
   - Use system accent color / custom accent picker
3. **Terminal**:
   - Default terminal emulator picker (detected installed terminals)
   - Terminal shell preference (default login shell / custom path)
4. **Advanced**:
   - Reset all view states button
   - Reveal database in Finder (Tags.sqlite)
   - Reveal SwiftData store in Finder
   - Check for updates (stub, reads GitHub releases API — optional, disabled by default)

**Requirements:**
- Use SwiftUI's `.settings { SettingsView() }` in `WindowGroup` for native macOS preferences.
- All settings stored in `UserDefaults` with `@AppStorage`.
- Changes apply immediately without restart.

**Acceptance criteria:**
- Cmd+, opens the preferences window.
- Changing default view mode to List affects new tabs/windows.
- Terminal picker shows only installed terminals.

---

## Prompt 15: Onboarding & Permissions

Implement the first-launch onboarding flow for permissions.

**Files to create/modify:**

### `Views/Onboarding/OnboardingView.swift`
```swift
struct OnboardingView: View {
    @State var step: OnboardingStep = .welcome
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    
    enum OnboardingStep {
        case welcome, permissions, favorites, complete
    }
}
```

**Steps:**
1. **Welcome** — Brief intro: "Nautica is a privacy-first file manager inspired by Nemo. No telemetry, no cloud, fully open source."
2. **Permissions** — Explain why Full Disk Access is needed. Button opens System Settings → Privacy & Security → Full Disk Access. Detect when permission is granted (poll `FileManager` readability of `/Users`).
3. **Favorites** — Pre-populate with standard folders; let user add/remove before finishing.
4. **Complete** — "You're ready." Button opens the main window.

**Requirements:**
- Show onboarding on first launch only (`hasCompletedOnboarding` flag).
- If permissions are denied, show a persistent banner in the main window with a button to reopen settings.
- Neurodivergent-friendly: no animations, clear buttons, predictable flow (no surprise modals).

**Acceptance criteria:**
- First launch shows onboarding before any main window.
- Permission step detects when access is granted and auto-advances.
- After onboarding, the flag is set and onboarding never shows again.

---

## Prompt 16: App Icon, Branding & Final Polish

Final polish pass before MVP shippable.

**Tasks:**
1. **App Icon**: Create an `AppIcon.appiconset` in Assets.xcassets. Use a simple nautical compass or Nautilus shell motif. Colors: system blue + accent. Provide all required sizes (16, 32, 128, 256, 512, 1024 @1x and @2x).
2. **Menu Bar**: Complete the application menu (Nautica, File, Edit, View, Go, Window, Help).
   - File: New Tab, New Window, Open, Get Info, Close
   - Edit: Cut, Copy, Paste, Select All, Preferences
   - View: as Icons, as List, Toggle Path Bar, Toggle Sidebar, Toggle Hidden Files, Enter Full Screen
   - Go: Back, Forward, Enclosing Folder, Home, Desktop, Documents, Downloads, Go to Folder…
   - Window: Minimize, Zoom, Show Previous Tab, Show Next Tab, Bring All to Front
   - Help: Search, Nautica Help (placeholder)
3. **Keyboard shortcuts**: Ensure all menu items have proper shortcuts matching the PRD and macOS conventions.
4. **Toolbar overflow**: Handle narrow windows — overflow items go into a "»" menu.
5. **Error handling**: Show user-friendly alerts for permission denied, file not found, disk full, etc.
6. **Sparkle updater stub**: Add `SPUUpdater` integration (Sparkle framework via SPM) but leave it disabled until v1.1.
7. **Build script**: Add a Run Script phase that:
   - Verifies no hardcoded paths
   - Runs `swiftlint` if installed (optional)
   - Strips debug symbols from release builds

**Acceptance criteria:**
- All menu items are functional and have correct shortcuts.
- App has a distinctive icon visible in Dock and About box.
- About box shows: app name, version, copyright, GPL-2.0+ notice, link to source code.
- Release build archives successfully for "Any Mac".

---

## Appendix: Prompt Dependency Order

Run prompts in this order. Each prompt assumes the files from previous prompts exist.

```
Prompt 0  ──► Prompt 1  ──► Prompt 2  ──► Prompt 3  ──► Prompt 4
(Project    (FS Models   (Selection   (Icon View    (List View
 Skeleton)   & Service)   Model)        NSCollectionView) NSTableView)
                │
                ▼
Prompt 5  ──► Prompt 6  ──► Prompt 7  ──► Prompt 8  ──► Prompt 9
(Sidebar)   (Path Bar)   (Toolbar)    (Tabs)       (Quick Look)
                │
                ▼
Prompt 10 ──► Prompt 11 ──► Prompt 12 ──► Prompt 13 ──► Prompt 14
(File Ops)  (Tag DB)     (SwiftData   (Terminal)   (Settings)
                          View State)
                │
                ▼
Prompt 15 ──► Prompt 16
(Onboarding) (Final Polish)
```

---

> **Note to Kimi Code**: If a prompt references a file that doesn't exist yet (e.g., `TagService` in Prompt 5), create a minimal stub (empty class/struct with the correct signature) so the project compiles. Do not implement stubbed functionality until its dedicated prompt arrives.
