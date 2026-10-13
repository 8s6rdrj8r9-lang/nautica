# Nautica — Product Requirements Document (PRD)

> **Codename**: Nautica (from Nemo → Captain Nemo → Nautilus → macOS-native file explorer)
> Version: v1.0 | Author: Arthur | Date: 2026-08-08
> Status: Draft
> **License**: GNU General Public License v2.0 or later (same as Nemo)

---

## 1. Overview

### 1.1 Background & Motivation

macOS Finder is visually polished but functionally stagnant. Power users—developers, creatives, and neurodivergent individuals who rely on visual organization and predictable navigation—consistently hit its limitations: no dual-pane browsing, no editable path bar, weak batch operations, and no native terminal integration. On Linux, **Nemo** (the Cinnamon file manager) solves many of these pain points with a pragmatic, fast, and configurable interface. However, Nemo is written in C/GTK and tied to the Linux desktop stack, making a direct port to macOS impossible.

There is no mature, open-source, native macOS file manager that bridges this gap. Commercial alternatives (Path Finder, ForkLift, Commander One) exist but are closed-source, expensive, and often abandonware-prone. **Nautica** aims to fill this gap: a Swift-native, open-source file manager that looks and feels like a first-class macOS app while delivering the power-user features that make Nemo indispensable.

### 1.2 Objectives

| Type | Objective |
|------|-----------|
| **Business** | Establish an open-source, privacy-first Finder alternative that builds brand equity for the `context_vault` / `au_genda` ecosystem. |
| **User** | Give macOS users a fast, predictable, visually organized file manager with power-user workflows (dual-pane, terminal launch, batch rename, path bar toggling) that Finder lacks. |
| **Success Metrics** | • Smooth 60fps browsing on directories with 10k+ files<br>• Zero-telemetry guarantee verified in network audit<br>• All Must Have features shippable within 8 weeks of MVP start |

### 1.3 Scope

- **In scope**: A native macOS file manager built in Swift/SwiftUI+AppKit featuring single-pane and dual-pane browsing, multiple view modes (icon, list, column preview), a sidebar with favorites and tree view, an editable/toggleable path bar, tabbed windows, Quick Look integration, terminal integration, batch rename, and file operation progress tracking.
- **Out of scope**: Windows or Linux ports, cloud-storage sync engines (Dropbox/iCloud Drive *integration* is fine, but we are not building a sync engine), built-in media player, or email attachment management.

---

## 2. User Personas

| Persona | Description |
|---------|-------------|
| **Power User Dev** | A software developer or DevOps engineer who lives in the terminal but needs a visual file manager for rapid navigation, drag-and-drop deployment bundles, and comparing directory trees side-by-side. |
| **Neurodivergent Creative** | A designer, writer, or artist with ADHD/Autism who relies on color-coded tags, consistent spatial layouts, and low-friction organization to maintain executive function and reduce cognitive load. |
| **Privacy-First Professional** | A lawyer, journalist, or researcher who refuses closed-source tools and telemetry, needs full local filesystem control, and audits every app for network activity. |

---

## 3. User Stories

### Power User Dev

| ID | Story |
|----|-------|
| US-PUD-01 | As a Power User Dev, I want to open two directories side-by-side in a single window, so that I can drag files between source and destination without managing multiple windows. |
| US-PUD-02 | As a Power User Dev, I want to open the current directory in Terminal via a keyboard shortcut or toolbar button, so that I can run scripts or git commands without re-navigating. |
| US-PUD-03 | As a Power User Dev, I want to toggle the path bar between a breadcrumb trail and an editable text field, so that I can either click to navigate or paste a deep path directly. |
| US-PUD-04 | As a Power User Dev, I want to see live progress (bytes transferred, ETA, per-file status) when copying large directories, so that I know whether I have time to grab coffee or if something is stuck. |

### Neurodivergent Creative

| ID | Story |
|----|-------|
| US-NDC-01 | As a Neurodivergent Creative, I want to assign colored tags to files and folders with custom labels, so that I can create a visual system that matches how I think (not just macOS's default 7 colors). |
| US-NDC-02 | As a Neurodivergent Creative, I want the file manager to remember my view settings (icon size, sort order, column widths) per-folder, so that I don't have to reconfigure the same view every time I return. |
| US-NDC-03 | As a Neurodivergent Creative, I want a predictable, distraction-free interface where optional toolbars and sidebars stay exactly where I put them, so that my workspace doesn't shift unexpectedly and trigger overwhelm. |
| US-NDC-04 | As a Neurodivergent Creative, I want to preview files (images, PDFs, text, audio) by pressing Space without opening another app, so that I can audit assets rapidly without losing my context. |

### Privacy-First Professional

| ID | Story |
|----|-------|
| US-PFP-01 | As a Privacy-First Professional, I want the app to function fully without any network access, so that I can verify with a firewall that zero telemetry is transmitted. |
| US-PFP-02 | As a Privacy-First Professional, I want full access to the entire filesystem (including hidden files and system directories) once I grant permissions, so that I am not artificially sandboxed like App Store apps. |
| US-PFP-03 | As a Privacy-First Professional, I want all preferences, tags, and window state stored in local plist/JSON files I can inspect and back up, so that my data never lives in an opaque cloud database. |

---

## 4. Functional Requirements

### 4.1 Feature List

| ID | Feature Name | User Story | Description | Input / Output / Interaction |
|----|-------------|------------|-------------|------------------------------|
| **F-001** | Icon View | US-NDC-02, US-NDC-04 | Browse files as a grid of icons with optional labels and preview thumbnails. | Input: Directory path. Output: Scrollable grid. Interaction: Click to select, double-click to open, Space for Quick Look. |
| **F-002** | List View | US-PUD-01, US-NDC-02 | Browse files as a multi-column table (Name, Size, Modified, Kind, Tags). | Input: Directory path. Output: Sortable table. Interaction: Column header click to sort, drag columns to resize. |
| **F-003** | Column Preview | US-NDC-04 | A rightmost pane showing a read-only preview of the selected file (text, image, PDF, audio waveform). | Input: Selected file path. Output: Rendered preview. Interaction: Auto-updates on selection change. |
| **F-004** | Dual Pane | US-PUD-01 | Split the window into two independent file browsers with a draggable divider. | Input: User toggle (Cmd+Shift+D or menu). Output: Two panes with independent navigation history. Interaction: Drag files across the divider to copy/move. |
| **F-005** | Sidebar | US-NDC-01, US-NDC-03 | A collapsible sidebar showing Favorites, Recent, Tags, and a directory Tree. | Input: User-configured favorites + filesystem scan. Output: Sidebar list. Interaction: Click to navigate, drag to reorder favorites. |
| **F-006** | Path Bar (Breadcrumb) | US-PUD-03 | A toolbar showing the current path as clickable segments (e.g., Home > Projects > Nautica). | Input: Current directory. Output: Horizontal button stack. Interaction: Click segment to jump up; right-click for ancestor list. |
| **F-007** | Path Bar (Editable) | US-PUD-03 | Toggle the path bar to a text field where users type or paste absolute/paths. | Input: User toggle (Cmd+L or click). Output: NSTextField. Interaction: Enter to navigate; tab-completion for paths. |
| **F-008** | Tabs | US-PUD-01 | Open multiple directories in tabs within a single window. | Input: User actions (Cmd+T, double-click folder with Cmd). Output: Tab bar. Interaction: Standard macOS tab behavior. |
| **F-009** | Quick Look | US-NDC-04 | Press Space to open a floating preview window for the selected file. | Input: Selected file + Space key. Output: Quick Look panel. Interaction: Standard macOS QLPreviewPanel. |
| **F-010** | Terminal Integration | US-PUD-02 | Open the current directory in Terminal.app or the default terminal emulator. | Input: User action (toolbar button or Cmd+Shift+T). Output: New terminal window/tab at current path. |
| **F-011** | File Operations | US-PUD-04, US-PFP-02 | Copy, move, delete, and rename files/directories with progress dialogs. | Input: User drag/drop or menu actions. Output: Progress window with cancel/pause. Interaction: Undo support (Cmd+Z). |
| **F-012** | Batch Rename | US-NDC-01 | Rename multiple selected files with patterns (sequence, find/replace, extension change). | Input: Multi-selection + dialog. Output: Renamed files. Interaction: Live preview of new names before confirm. |
| **F-013** | Custom Tags | US-NDC-01 | Assign user-defined colored tags with custom labels to any file/folder. | Input: Right-click menu or sidebar. Output: Tag metadata stored in local SQLite database. Interaction: Filter by tag, sort by tag. |
| **F-014** | Per-Folder View State | US-NDC-02 | Remember view mode, sort column, icon size, and column widths for each directory. | Input: User changes. Output: Stored in **SwiftData**. Interaction: Auto-restore on revisit. |
| **F-015** | Hidden Files Toggle | US-PFP-02 | Show/hide dotfiles and system-hidden items. | Input: Cmd+Shift+. or menu. Output: View refresh. Interaction: Persistent per-session. |
| **F-016** | Network Share Browsing | US-PUD-01 | Connect to and browse SMB, AFP, and WebDAV shares. | Input: Server URL or Bonjour discovery. Output: Mounted share in sidebar. Interaction: Authenticate via system dialog. |

### 4.2 Non-Functional Requirements

| Dimension | Requirement |
|-----------|-------------|
| **Performance** | • Icon view must render 10,000+ files at 60fps with lazy thumbnail loading.<br>• List view sort on 50k files must complete in < 500ms.<br>• Window open time < 300ms for last-used directory. |
| **Security** | • Zero network calls unless user explicitly mounts a network share.<br>• All file access via `NSFileCoordinator` to prevent conflicts.<br>• No keychain access except for network share credentials (stored in system keychain, not custom). |
| **Availability** | • Local-first: all data stored on-device; no cloud dependency.<br>• Crash recovery: restore open windows/tabs on relaunch. |
| **Scalability** | • Plugin architecture (future) for custom view modes and sidebar providers.<br>• Tag database must handle 100k+ tagged items without degradation. |
| **Usability** | • Follow Apple HIG for all controls, menus, and keyboard shortcuts.<br>• Neurodivergent-friendly: consistent layout, predictable animations (reduce motion respected), high-contrast support.<br>• Full keyboard navigation support (arrow keys, type-ahead selection, Cmd+number for tabs). |
| **Compatibility** | • macOS 14 (Sonoma) minimum, optimized for macOS 15+.<br>• Apple Silicon and Intel.<br>• Integrates with macOS Services menu and Share extensions. |

### 4.3 Feature Dependencies

```
F-001 Icon View ──┬──► F-004 Dual Pane (needs a view to duplicate)
F-002 List View ──┘
                  
F-006 Path Bar (Breadcrumb) ──► F-007 Path Bar (Editable)
                              (editable is a mode of the same bar)

F-001/F-002 ──► F-009 Quick Look (needs a selection model)
F-001/F-002 ──► F-011 File Operations (needs selection + drag source)
F-005 Sidebar ──► F-013 Custom Tags (tags need a sidebar section)
F-011 File Operations ──► F-012 Batch Rename (batch is a multi-file operation)
```

---

## 5. Prioritization

### 5.1 MoSCoW Matrix

| Feature ID | Feature Name | Priority | Rationale |
|------------|-------------|----------|-----------|
| F-001 | Icon View | **Must** | Core browsing experience; product is unusable without it. |
| F-002 | List View | **Must** | Core browsing experience; power users need tabular data. |
| F-005 | Sidebar | **Must** | Essential navigation aid; required for favorites and tree. |
| F-006 | Path Bar (Breadcrumb) | **Must** | Critical for orientation and navigation; expected by all users. |
| F-008 | Tabs | **Must** | Basic window management; standard macOS convention. |
| F-009 | Quick Look | **Must** | macOS-standard preview; users expect Space to work. |
| F-011 | File Operations | **Must** | Copy/move/delete are the fundamental purpose of a file manager. |
| F-015 | Hidden Files Toggle | **Must** | Required for power users and privacy-first workflows. |
| F-004 | Dual Pane | **Should** | Signature Nemo feature; differentiates from Finder. Defer to v1.1 if needed. |
| F-007 | Path Bar (Editable) | **Should** | High-value for keyboard-centric users; a clear upgrade over Finder. |
| F-010 | Terminal Integration | **Should** | Core Nemo feature; developer persona depends on it. |
| F-012 | Batch Rename | **Should** | Common power-user task; Finder requires third-party tools for this. |
| F-014 | Per-Folder View State | **Should** | High-value for neurodivergent users; moderate implementation cost. |
| F-003 | Column Preview | **Could** | Nice enhancement to list view; not critical for MVP. |
| F-013 | Custom Tags | **Could** | Differentiator, but macOS already has Finder tags; we need a stronger angle before prioritizing. |
| F-016 | Network Share Browsing | **Could** | Important for some users, but macOS Finder handles this adequately; we can mount via Finder and browse local mount. |
| — | Plugin Architecture | **Won't Have** | Critical for long-term ecosystem but far beyond MVP scope; defer to v2.0. |
| — | Cloud Sync Engine | **Won't Have** | Explicitly out of scope; we are not building Dropbox. |
| — | Windows/Linux Port | **Won't Have** | macOS-native is the core value proposition; cross-platform would dilute the native experience. |

### 5.2 Release Planning Recommendations

- **MVP (v1.0)**: F-001, F-002, F-005, F-006, F-008, F-009, F-011, F-015
  - *Goal*: A solid, fast Finder replacement that feels native and handles 90% of daily file tasks.
- **v1.1**: F-004, F-007, F-010, F-012, F-014
  - *Goal*: Add the Nemo-inspired power-user features that differentiate Nautica from Finder.
- **v2.0 (evaluate)**: F-003, F-013, F-016, Plugin Architecture
  - *Goal*: Premium features and extensibility.

---

## 6. Acceptance Criteria

### F-001 Icon View

**AC-F001-01: Basic rendering**
Given the user has navigated to a directory containing 50 mixed files and folders
When the view loads
Then all items render as icons with names beneath them, and the layout reflows responsively as the window resizes.

**AC-F001-02: Large directory performance**
Given the user has navigated to a directory containing 15,000 files
When the view loads
Then the initial render completes in under 500ms, thumbnails load progressively, and scrolling remains at 60fps.

**AC-F001-03: Selection and interaction**
Given the user sees the icon view
When they click an item, Shift-click another, and Cmd-click a third
Then the first item is selected, the range between first and second is selected, and the third is added to the selection.

### F-002 List View

**AC-F002-01: Column sort**
Given the user is in list view with files of varying sizes and dates
When they click the "Size" column header
Then the list re-sorts by size ascending; a second click sorts descending.

**AC-F002-02: Type-ahead selection**
Given the user is in list view
When they type "pro" rapidly
Then the selection jumps to the first item starting with "pro" (case-insensitive).

**AC-F002-03: Column persistence**
Given the user drags the "Modified" column to be the first column and resizes it to 200px
When they close and reopen the same directory
Then the "Modified" column remains first and 200px wide.

### F-005 Sidebar

**AC-F005-01: Favorites navigation**
Given the user has added `~/Projects` to favorites
When they click "Projects" in the sidebar
Then the main view navigates to `~/Projects`.

**AC-F005-02: Tree expansion**
Given the user clicks the disclosure triangle next to their home directory in the Tree section
When the triangle rotates down
Then the immediate subdirectories load and display beneath the home directory.

**AC-F005-03: Sidebar collapse**
Given the user drags the sidebar divider to the left edge
When the divider snaps to 0 width
Then the sidebar hides completely and a toolbar button appears to restore it.

### F-006 Path Bar (Breadcrumb)

**AC-F006-01: Segment navigation**
Given the user is in `/Users/arthur/Projects/Nautica/Source`
When they click the "Projects" segment
Then the view navigates to `/Users/arthur/Projects`.

**AC-F006-02: Ancestor menu**
Given the user right-clicks the "Nautica" segment
When the context menu appears
Then it lists all sibling folders within `/Users/arthur/Projects` for rapid switching.

**AC-F006-03: Draggable segments**
Given the user drags the "Nautica" segment to the sidebar
When they release over the Favorites area
Then `/Users/arthur/Projects/Nautica` is added as a new favorite.

### F-008 Tabs

**AC-F008-01: New tab**
Given the user presses Cmd+T
When the action fires
Then a new tab opens duplicating the current directory, and focus shifts to it.

**AC-F008-02: Tab persistence**
Given the user has 3 tabs open with different directories
When they close the window and reopen the app
Then the same 3 tabs restore with the same directories selected.

**AC-F008-03: Background tab drag**
Given the user drags a file from the active tab
When they hover over a background tab
Then the background tab becomes active after a 600ms delay, allowing drop navigation.

### F-009 Quick Look

**AC-F009-01: Space activation**
Given a file is selected
When the user presses Space
Then the macOS Quick Look panel opens for that file within 100ms.

**AC-F009-02: Arrow navigation in preview**
Given Quick Look is open on a file
When the user presses Down arrow
Then Quick Look closes and reopens on the next file in the current view.

### F-011 File Operations

**AC-F011-01: Copy progress**
Given the user copies a 5GB directory containing 10,000 files
When the operation starts
Then a progress window appears showing overall percentage, current file name, bytes transferred, and ETA; the operation completes without blocking the main UI.

**AC-F011-02: Cancel operation**
Given a copy operation is in progress
When the user clicks Cancel
Then the operation halts within 2 seconds, partially copied files are cleaned up, and the destination returns to its pre-operation state.

**AC-F011-03: Undo support**
Given the user deletes a file
When they press Cmd+Z within 30 seconds
Then the file is restored to its original location.

### F-015 Hidden Files Toggle

**AC-F015-01: Toggle visibility**
Given a directory contains `.gitignore` and `README.md`
When the user presses Cmd+Shift+.
Then `.gitignore` appears in the view; pressing the shortcut again hides it.

**AC-F015-02: Session persistence**
Given hidden files are visible
When the user navigates to a different directory
Then hidden files remain visible in the new directory.

### F-004 Dual Pane (Should Have)

**AC-F004-01: Toggle dual pane**
Given the user is in a single-pane window
When they press Cmd+Shift+D
Then the window splits into two equal panes, each showing the current directory.

**AC-F004-02: Cross-pane drag**
Given dual pane is active with `/Source` in the left pane and `/Dest` in the right
When the user drags a file from left to right
Then a copy operation initiates with a progress dialog.

### F-007 Path Bar (Editable) (Should Have)

**AC-F007-01: Toggle to text**
Given the breadcrumb path bar is visible
When the user presses Cmd+L
Then the bar transforms into an editable text field containing the absolute path.

**AC-F007-02: Path completion**
Given the editable path bar is active
When the user types `~/Pro` and presses Tab
Then the text auto-completes to `~/Projects/` if that directory exists.

### F-010 Terminal Integration (Should Have)

**AC-F010-01: Open in Terminal**
Given the user is browsing `/Users/arthur/Projects`
When they press Cmd+Shift+T
Then Terminal.app opens a new window with working directory set to `/Users/arthur/Projects`.

**AC-F010-02: Terminal preference**
Given the user has set iTerm2 as the default terminal in Nautica preferences
When they invoke the open-in-terminal action
Then iTerm2 opens instead of Terminal.app.

### F-012 Batch Rename (Should Have)

**AC-F012-01: Sequence rename**
Given the user selects 5 files named `img1.jpg`, `img2.jpg`, etc.
When they apply a batch rename pattern `vacation_###.jpg`
Then the files are renamed to `vacation_001.jpg` through `vacation_005.jpg`.

**AC-F012-02: Preview before apply**
Given the user configures a batch rename operation
When the dialog shows the preview list
Then each row displays the original name and the new name side-by-side, with conflicts highlighted in red.

### F-014 Per-Folder View State (Should Have)

**AC-F014-01: View mode persistence**
Given the user sets `~/Photos` to icon view with 128px icons
When they navigate away, then return to `~/Photos`
Then the view restores to icon view 128px icons.

**AC-F014-02: Sort persistence**
Given the user sorts `~/Downloads` by "Date Added" descending
When they return to `~/Downloads` after restarting the app
Then the list is still sorted by "Date Added" descending.

---

## 7. Assumptions & Constraints

### 7.1 Assumptions

- Users are on macOS 14 (Sonoma) or later; we do not support macOS 13 or earlier.
- The app will be distributed outside the Mac App Store (via GitHub releases, Homebrew Cask, or direct DMG) because full filesystem access and the level of sandboxing required are incompatible with App Store restrictions.
- Users willing to adopt a Finder alternative are comfortable granting Full Disk Access or folder-level permissions.
- Thumbnail generation will leverage macOS's existing `QLThumbnailGenerator` API rather than building custom image parsers.
- Tag metadata will be stored in a **local SQLite database** (`~/Library/Application Support/Nautica/Tags.sqlite`) for flexibility and queryability.
- Per-folder view state and preferences will be stored using **SwiftData** (consistent with the au_genda stack).

### 7.2 Constraints

| Type | Constraint |
|------|------------|
| **Technical** | Swift 5.9+, SwiftUI for chrome/toolbars, AppKit (`NSCollectionView`/`NSTableView`) for file listings due to SwiftUI performance limits at 10k+ items. |
| **Business** | Open-source under **GPL-2.0 or later** (same as Nemo). Zero telemetry is a hard requirement—no analytics, crash reporting, or network calls without explicit user opt-in. |
| **Timeline** | MVP Must Have features should be demonstrable within 8 weeks of focused development. |

### 7.3 Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| SwiftUI performance degrades with large directories (>10k items) | High | High | Use AppKit `NSCollectionView` for the file grid; SwiftUI only for chrome. Benchmark early. |
| macOS permission dialogs frustrate users (Full Disk Access) | Medium | High | Provide a clear onboarding flow explaining *why* permissions are needed; never ask for more than necessary. |
| Finder integration (e.g., "Set as default file manager") is not officially supported by macOS | Medium | Medium | Position as a standalone app, not a Finder replacement; integrate via Services menu and Share extensions instead. |
| Thumbnail generation for non-native formats (RAW, PSD) is slow | Low | Medium | Use `QLThumbnailGenerator` with asynchronous loading and placeholder icons; cancel generation for off-screen items. |
| Competing with free Finder is psychologically hard for users | Medium | Medium | Focus on *distinctive* features (dual pane, terminal, batch rename) that Finder genuinely lacks; market to power users. |

---

## 8. Open Questions

- [x] **License**: **GPL-2.0 or later** (same as Nemo) — copyleft ensures derivatives stay open.
- [x] **Tag storage**: **SQLite database** at `~/Library/Application Support/Nautica/Tags.sqlite` — more flexible and queryable than xattr.
- [ ] **Default terminal**: Should we auto-detect iTerm2/Kitty/Warp, or require user preference? Auto-detect adds complexity but improves first-run experience.
- [ ] **Columns view**: Should we replicate Finder's Columns view (NeXT-style browser) as a first-class view mode, or treat Column Preview (F-003) as sufficient?
- [ ] **Localization**: English-only for v1.0, or plan i18n infrastructure from day one given the au_genda localization experience?
- [x] **SwiftData vs Core Data vs plain files**: **SwiftData** for per-folder view state and preferences — consistent with au_genda stack.

---

## Appendix

### A. Glossary

| Term | Definition |
|------|------------|
| **Nemo** | The default file manager of the Cinnamon desktop environment (Linux); the primary UX inspiration for Nautica. |
| **xattr** | Extended file attributes on Unix-like systems; used by macOS Finder for tags and comments. |
| **QLThumbnailGenerator** | macOS API for asynchronously generating thumbnails for files using the system's Quick Look architecture. |
| **NSFileCoordinator** | macOS API for coordinating file access between processes to prevent data corruption. |
| **FSEvents** | macOS filesystem event notification API; used to watch for directory changes without polling. |

### B. Reference Links

- Nemo Source: https://github.com/linuxmint/nemo
- Apple HIG (macOS): https://developer.apple.com/design/human-interface-guidelines/macos
- NSFileCoordinator Docs: https://developer.apple.com/documentation/foundation/nsfilecoordinator
- QLThumbnailGenerator Docs: https://developer.apple.com/documentation/quicklook/qllib/thumbnail generation

### C. Nemo Feature Inventory (for v1.1+ consideration)

Features present in Nemo that are **not** in the MVP but worth tracking:

- "Open as Root" (macOS equivalent: authenticate for admin operations)
- Native FTP/SFTP client (macOS Finder already supports read-only FTP; full SFTP is v2.0)
- Custom context-menu Actions (Nemo's "Spices" — maps to our plugin architecture)
- File operation queueing (pause/resume/reorder)
- Recursive search within current folder (Spotlight alternative)
- Bulk file permissions editor
- Customizable toolbar (drag-to-reorder buttons)
