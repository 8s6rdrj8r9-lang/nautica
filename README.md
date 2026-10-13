# Nautica

A privacy-first, native macOS file manager inspired by Nemo (Linux Cinnamon).
No telemetry, no cloud, fully open source (GPL-2.0 or later).

- **Requires**: macOS 14.0+ (Sonoma), Xcode 16+
- **Stack**: Swift 5.9+, SwiftUI (chrome/toolbars), AppKit (`NSCollectionView`/`NSTableView`)
  for file listings, SwiftData (per-folder view state), GRDB/SQLite (tags), Combine
- **Spec**: see `../Nautica-PRD-v1.0.md` and `../Nautica-KimiCode-Prompts.md`

## Building

```sh
xcodebuild -project Nautica.xcodeproj -scheme Nautica -configuration Debug build
```

Or open `Nautica.xcodeproj` in Xcode and press ⌘R. The only external dependency
is [GRDB.swift](https://github.com/groue/GRDB.swift), fetched automatically via
Swift Package Manager.

The build is signed to run locally (ad-hoc). Full filesystem access is requested
via the `com.apple.security.files.*` entitlements; for unrestricted browsing,
grant the app Full Disk Access in System Settings → Privacy & Security.

## Architecture

```
Nautica/
├── NauticaApp.swift            # App entry (@main), WindowGroup + Settings scene,
│                               #   menu commands, AppDelegate (tab restore, DB setup)
├── Info.plist                  # Declares public.folder document type
├── Credits.rtf                 # About-box credits (GPL-2.0+)
├── Nautica.entitlements        # User-selected + full-disk file access
├── Assets.xcassets/            # AppIcon (generated compass-star motif)
├── Models/                     # FileItem, DirectoryContents, SelectionModel,
│                               #   NavigationHistory, TabState, TabPersistence,
│                               #   TagItem/FileTag (GRDB), FolderViewState (SwiftData)
├── Services/                   # FileSystemService, FileOperationService, TagService (GRDB),
│                               #   QuickLookService, TerminalService — actors, UI-agnostic;
│                               #   ViewStateService (@MainActor, SwiftData)
├── Views/
│   ├── BrowserView.swift       # NavigationSplitView: sidebar + detail, file ops,
│   │                           #   Quick Look, per-folder state, permission banner
│   ├── SidebarView.swift       # Favorites / Tree / Tags / Recent
│   ├── FileViews/              # AppKit-backed file listings (Icon, List) hosted
│   │                           #   via FileViewCoordinator (NSViewRepresentable)
│   ├── Chrome/                 # PathBarView (breadcrumbs), BrowserToolbar (NSToolbar),
│   │                           #   ProgressPanel (file-op progress sheet)
│   ├── Settings/               # SettingsView (General/Appearance/Terminal/Advanced)
│   ├── Onboarding/             # OnboardingView (first-launch: welcome, FDA, favorites)
│   └── Windows/MainWindow.swift
└── Utilities/                  # Constants, URL/FileManager/Color extensions
```

Design rules:

- **SwiftUI for chrome, AppKit for listings.** SwiftUI grids degrade past ~10k items;
  `NSCollectionView`/`NSTableView` give 60fps scrolling and mature selection/drag behavior.
- **Services are actors.** All file I/O goes through `NSFileCoordinator` and stays off
  the main thread; views observe `@Observable` models.
- **Local-first.** Tags live in `~/Library/Application Support/Nautica/Tags.sqlite`
  (GRDB); per-folder view state lives in SwiftData; preferences in `UserDefaults`.
- **Zero network calls** except explicit user actions (e.g., mounting a share).

## Implementation order

The app is built prompt-by-prompt per `Nautica-KimiCode-Prompts.md`
(scaffold → file system → selection → views → chrome → services → polish).
Each source file notes which prompt implements it.

## Graph organization and PAF

Nautica also provides an Objects & Views workspace backed by the existing GRDB
stack. Objects can appear in multiple Collection, Smart, and Relationship Views;
Views do not own their Objects. Settings → Right Dock configures independent
navigation pins for Views, Objects, registered Subsystems, and actions. The
existing filesystem browser remains available through Files.

PAF is a package-driven subsystem with ZIP/manifest integrity checks, grouped
intake, explicit boundary/evidence review, immutable freeze, a standalone auditor
export, and frozen response capture. Execution currently uses an external auditor
through manual export/import; there is no embedded model runner. See
[Graph and PAF architecture](docs/GRAPH-AND-PAF.md) for the package contract,
history semantics, security limits, and test coverage.
