import AppKit
import Foundation
import Quartz
import SwiftUI

/// View controller presenting files in a Finder-style Gallery View (⌘4).
/// Features a central Quartz QLPreviewView canvas for interactive preview of images,
/// PDFs, audio, video, text, and 3D models, with a horizontal scrolling thumbnail
/// filmstrip below and arrow key navigation.
final class GalleryViewController: NSViewController {
    let directoryContents: DirectoryContents
    let selectionModel: SelectionModel

    var onNavigate: ((URL) -> Void)?
    var keyDownHandler: ((NSEvent) -> Bool)?
    var onRenameRequest: (() -> Void)?
    var onCopySelection: (() -> Void)?
    var onTrashSelection: (() -> Void)?
    var onQuickLook: (() -> Void)?
    var onGetInfo: (() -> Void)?
    var onCompressWithPassword: (([URL]) -> Void)?
    var onFindDuplicates: ((URL) -> Void)?
    var onGitDiff: ((URL) -> Void)?
    var onGitCommit: (() -> Void)?

    private let splitContainer = NSView()
    private let previewContainer = NSView()
    private var activePreviewView: QLPreviewView?
    private var folderFallbackHost: NSHostingView<GalleryFolderView>?

    private let quickActionBar = NSStackView()
    private var rotateLeftBtn: NSButton?
    private var rotateRightBtn: NSButton?

    private let filmstripScrollView = NSScrollView()
    private let filmstripStack = NSStackView()
    private var filmstripItemViews: [UUID: GalleryThumbnailItemView] = [:]

    private var items: [FileItem] = []
    private var currentPreviewURL: URL?

    init(directoryContents: DirectoryContents, selectionModel: SelectionModel) {
        self.directoryContents = directoryContents
        self.selectionModel = selectionModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        splitContainer.translatesAutoresizingMaskIntoConstraints = false

        // 1. Preview Container
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.wantsLayer = true
        previewContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // 2. Quick Action Bar
        quickActionBar.orientation = .horizontal
        quickActionBar.alignment = .centerY
        quickActionBar.spacing = 10
        quickActionBar.translatesAutoresizingMaskIntoConstraints = false
        setupQuickActions()

        // 3. Filmstrip Scroll View
        filmstripScrollView.hasHorizontalScroller = true
        filmstripScrollView.hasVerticalScroller = false
        filmstripScrollView.autohidesScrollers = true
        filmstripScrollView.drawsBackground = false
        filmstripScrollView.translatesAutoresizingMaskIntoConstraints = false

        filmstripStack.orientation = .horizontal
        filmstripStack.alignment = .centerY
        filmstripStack.spacing = 8
        filmstripStack.translatesAutoresizingMaskIntoConstraints = false

        let clipView = NSClipView()
        clipView.documentView = filmstripStack
        clipView.drawsBackground = false
        filmstripScrollView.contentView = clipView

        splitContainer.addSubview(previewContainer)
        splitContainer.addSubview(quickActionBar)
        splitContainer.addSubview(filmstripScrollView)

        NSLayoutConstraint.activate([
            // Preview Container at top
            previewContainer.topAnchor.constraint(equalTo: splitContainer.topAnchor),
            previewContainer.leadingAnchor.constraint(equalTo: splitContainer.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: splitContainer.trailingAnchor),
            previewContainer.bottomAnchor.constraint(equalTo: quickActionBar.topAnchor, constant: -8),

            // Quick Action Bar in middle
            quickActionBar.leadingAnchor.constraint(equalTo: splitContainer.leadingAnchor, constant: 16),
            quickActionBar.trailingAnchor.constraint(equalTo: splitContainer.trailingAnchor, constant: -16),
            quickActionBar.heightAnchor.constraint(equalToConstant: 28),
            quickActionBar.bottomAnchor.constraint(equalTo: filmstripScrollView.topAnchor, constant: -8),

            // Filmstrip at bottom (fixed height ~96pt)
            filmstripScrollView.leadingAnchor.constraint(equalTo: splitContainer.leadingAnchor),
            filmstripScrollView.trailingAnchor.constraint(equalTo: splitContainer.trailingAnchor),
            filmstripScrollView.heightAnchor.constraint(equalToConstant: 96),
            filmstripScrollView.bottomAnchor.constraint(equalTo: splitContainer.bottomAnchor, constant: -6),

            // Pin filmstrip stack to clipview
            filmstripStack.topAnchor.constraint(equalTo: clipView.topAnchor),
            filmstripStack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor, constant: 12),
            filmstripStack.bottomAnchor.constraint(equalTo: clipView.bottomAnchor),
            filmstripStack.heightAnchor.constraint(equalTo: clipView.heightAnchor),
        ])

        view = splitContainer
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadData()
    }

    func reloadData() {
        items = directoryContents.items
        rebuildFilmstrip()
        updateSelectionAndPreview()
    }

    private func setupQuickActions() {
        let qlButton = NSButton(title: "Quick Look", target: self, action: #selector(quickLookClicked))
        qlButton.bezelStyle = .rounded
        qlButton.controlSize = .small
        qlButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Quick Look")

        let openButton = NSButton(title: "Open", target: self, action: #selector(openClicked))
        openButton.bezelStyle = .rounded
        openButton.controlSize = .small
        openButton.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: "Open")

        let rotLeft = NSButton(image: NSImage(systemSymbolName: "rotate.left", accessibilityDescription: "Rotate Left")!, target: self, action: #selector(rotateLeftClicked))
        rotLeft.bezelStyle = .rounded
        rotLeft.controlSize = .small
        rotLeft.toolTip = "Rotate Left"
        rotateLeftBtn = rotLeft

        let rotRight = NSButton(image: NSImage(systemSymbolName: "rotate.right", accessibilityDescription: "Rotate Right")!, target: self, action: #selector(rotateRightClicked))
        rotRight.bezelStyle = .rounded
        rotRight.controlSize = .small
        rotRight.toolTip = "Rotate Right"
        rotateRightBtn = rotRight

        quickActionBar.addArrangedSubview(qlButton)
        quickActionBar.addArrangedSubview(openButton)
        quickActionBar.addArrangedSubview(rotLeft)
        quickActionBar.addArrangedSubview(rotRight)
    }

    private func rebuildFilmstrip() {
        filmstripStack.arrangedSubviews.forEach {
            filmstripStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        filmstripItemViews.removeAll()

        for item in items {
            let itemView = GalleryThumbnailItemView(item: item)
            itemView.translatesAutoresizingMaskIntoConstraints = false
            itemView.widthAnchor.constraint(equalToConstant: 72).isActive = true
            itemView.heightAnchor.constraint(equalToConstant: 86).isActive = true

            itemView.onClick = { [weak self] in
                self?.selectionModel.select(item.id, modifierFlags: [])
                self?.updateSelectionAndPreview()
            }
            itemView.onDoubleClick = { [weak self] in
                guard let self else { return }
                if ArchiveService.shared.isArchive(url: item.url) {
                    Task {
                        do {
                            _ = try await ArchiveService.shared.extract(archiveURL: item.url)
                            await MainActor.run {
                                self.directoryContents.reload()
                                self.reloadData()
                            }
                        } catch {
                            await MainActor.run { NSAlert(error: error).runModal() }
                        }
                    }
                } else if ArchiveService.shared.isDiskImage(url: item.url) {
                    Task {
                        do {
                            let mountPoint = try await ArchiveService.shared.attachDiskImage(at: item.url)
                            await MainActor.run { self.onNavigate?(mountPoint) }
                        } catch {
                            await MainActor.run { NSAlert(error: error).runModal() }
                        }
                    }
                } else if item.isDirectory {
                    self.onNavigate?(item.url)
                } else {
                    NSWorkspace.shared.open(item.url)
                }
            }
            itemView.onRightClick = { [weak self] event in
                self?.showContextMenu(for: item, event: event)
            }

            filmstripStack.addArrangedSubview(itemView)
            filmstripItemViews[item.id] = itemView
        }
    }

    func updateSelectionAndPreview() {
        let selectedIDs = selectionModel.selectedIDs
        for (id, itemView) in filmstripItemViews {
            itemView.isSelected = selectedIDs.contains(id)
        }

        // Get currently focused item
        let activeItem: FileItem?
        if let last = selectionModel.lastClickedID, let item = items.first(where: { $0.id == last }) {
            activeItem = item
        } else if let firstID = selectedIDs.first, let item = items.first(where: { $0.id == firstID }) {
            activeItem = item
        } else {
            activeItem = items.first
            if let first = activeItem {
                selectionModel.select(first.id, modifierFlags: [])
                filmstripItemViews[first.id]?.isSelected = true
            }
        }

        guard let targetItem = activeItem else {
            clearPreview()
            return
        }

        updatePreview(for: targetItem)
        scrollToSelectedItem(targetItem.id)
    }

    private func updatePreview(for item: FileItem) {
        let isImage = ["png", "jpg", "jpeg", "heic", "tiff", "webp", "gif"].contains(item.url.pathExtension.lowercased())
        rotateLeftBtn?.isHidden = !isImage
        rotateRightBtn?.isHidden = !isImage

        if item.isDirectory {
            // Show folder fallback view
            activePreviewView?.removeFromSuperview()
            activePreviewView = nil

            folderFallbackHost?.removeFromSuperview()
            let host = NSHostingView(rootView: GalleryFolderView(item: item, onOpen: { [weak self] in
                self?.onNavigate?(item.url)
            }))
            host.translatesAutoresizingMaskIntoConstraints = false
            previewContainer.addSubview(host)
            NSLayoutConstraint.activate([
                host.topAnchor.constraint(equalTo: previewContainer.topAnchor),
                host.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
                host.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
            ])
            folderFallbackHost = host
            currentPreviewURL = item.url
        } else {
            folderFallbackHost?.removeFromSuperview()
            folderFallbackHost = nil

            if activePreviewView == nil {
                let preview = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
                preview.translatesAutoresizingMaskIntoConstraints = false
                preview.autostarts = true
                previewContainer.addSubview(preview)
                NSLayoutConstraint.activate([
                    preview.topAnchor.constraint(equalTo: previewContainer.topAnchor),
                    preview.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
                    preview.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
                    preview.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
                ])
                activePreviewView = preview
            }

            activePreviewView?.previewItem = item.url as QLPreviewItem
            currentPreviewURL = item.url
        }
    }

    private func clearPreview() {
        activePreviewView?.removeFromSuperview()
        activePreviewView = nil
        folderFallbackHost?.removeFromSuperview()
        folderFallbackHost = nil
        currentPreviewURL = nil
    }

    private func scrollToSelectedItem(_ id: UUID) {
        guard let itemView = filmstripItemViews[id] else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.filmstripScrollView.contentView.scrollToVisible(itemView.frame)
            self.filmstripScrollView.reflectScrolledClipView(self.filmstripScrollView.contentView)
        }
    }

    // MARK: - Traversal Actions

    func selectPrevious() {
        guard !items.isEmpty else { return }
        let currentID = selectionModel.lastClickedID ?? selectionModel.selectedIDs.first
        let currentIndex = items.firstIndex(where: { $0.id == currentID }) ?? 0
        let prevIndex = max(0, currentIndex - 1)
        let newItem = items[prevIndex]
        selectionModel.select(newItem.id, modifierFlags: [])
        updateSelectionAndPreview()
    }

    func selectNext() {
        guard !items.isEmpty else { return }
        let currentID = selectionModel.lastClickedID ?? selectionModel.selectedIDs.first
        let currentIndex = items.firstIndex(where: { $0.id == currentID }) ?? 0
        let nextIndex = min(items.count - 1, currentIndex + 1)
        let newItem = items[nextIndex]
        selectionModel.select(newItem.id, modifierFlags: [])
        updateSelectionAndPreview()
    }

    @objc private func quickLookClicked() {
        onQuickLook?()
    }

    @objc private func openClicked() {
        guard let currentID = selectionModel.lastClickedID ?? selectionModel.selectedIDs.first,
              let item = items.first(where: { $0.id == currentID }) else { return }
        if item.isDirectory {
            onNavigate?(item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    @objc private func rotateLeftClicked() {
        rotateImage(by: 270)
    }

    @objc private func rotateRightClicked() {
        rotateImage(by: 90)
    }

    private func rotateImage(by degrees: Int) {
        guard let url = currentPreviewURL else { return }
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            process.arguments = ["-r", "\(degrees)", url.path]
            try? process.run()
            process.waitUntilExit()

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.directoryContents.reload()
                self.reloadData()
            }
        }
    }

    private func showContextMenu(for item: FileItem, event: NSEvent) {
        selectionModel.select(item.id, modifierFlags: [])
        updateSelectionAndPreview()

        let isGit = GitService.shared.isGitRepository(at: directoryContents.url)
        let actions = FileContextMenu.Actions(
            open: { [weak self] in
                if item.isDirectory { self?.onNavigate?(item.url) } else { NSWorkspace.shared.open(item.url) }
            },
            openWith: { appURL in
                NSWorkspace.shared.open([item.url], withApplicationAt: appURL, configuration: .init())
            },
            quickLook: { [weak self] in self?.onQuickLook?() },
            getInfo: { GetInfoService.shared.showInfo(for: item.url) },
            rename: { [weak self] in self?.onRenameRequest?() },
            copy: { [weak self] in self?.onCopySelection?() },
            trash: { [weak self] in self?.onTrashSelection?() },
            share: { [weak self] in
                let picker = NSSharingServicePicker(items: [item.url])
                if let view = self?.view {
                    picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
                }
            },
            compress: {
                let targetDir = item.url.deletingLastPathComponent()
                let zipURL = targetDir.appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent).zip")
                Task.detached {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", item.url.path, zipURL.path]
                    try? p.run()
                    p.waitUntilExit()
                }
            },
            extract: { [weak self] in
                guard let self else { return }
                Task {
                    do {
                        _ = try await ArchiveService.shared.extract(archiveURL: item.url)
                        await MainActor.run {
                            self.directoryContents.reload()
                            self.reloadData()
                        }
                    } catch {
                        await MainActor.run { NSAlert(error: error).runModal() }
                    }
                }
            },
            mountDiskImage: { [weak self] in
                guard let self else { return }
                Task {
                    do {
                        let mount = try await ArchiveService.shared.attachDiskImage(at: item.url)
                        await MainActor.run { self.onNavigate?(mount) }
                    } catch {
                        await MainActor.run { NSAlert(error: error).runModal() }
                    }
                }
            },
            compressWithPassword: { [weak self] in
                self?.onCompressWithPassword?([item.url])
            },
            createSymlink: {
                let target = item.url.deletingLastPathComponent().appendingPathComponent("\(item.name) symlink")
                try? FileManager.default.createSymbolicLink(at: target, withDestinationURL: item.url)
            },
            copyPath: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            },
            openInTerminal: { [weak self] in
                let targetFolder = item.isDirectory ? item.url : item.url.deletingLastPathComponent()
                Task {
                    try? await TerminalService.shared.openTerminal(
                        at: targetFolder,
                        emulator: TerminalService.shared.defaultTerminal()
                    )
                }
            },
            makeAlias: { [weak self] in
                guard let self else { return }
                let dest = self.directoryContents.url
                Task {
                    _ = await FileOperationService.shared.makeAliases(for: [item.url], in: dest)
                    await MainActor.run {
                        self.directoryContents.reload()
                        self.reloadData()
                    }
                }
            },
            showOriginal: { [weak self] in
                if let targetURL = item.resolvedTargetURL ?? FileOperationService.shared.resolveTarget(for: item.url) {
                    let parentURL = targetURL.deletingLastPathComponent().standardizedFileURL
                    self?.onNavigate?(parentURL)
                }
            },
            rotateLeft: { [weak self] in
                self?.rotateImage(by: 270)
            },
            rotateRight: { [weak self] in
                self?.rotateImage(by: 90)
            },
            createPDF: { [weak self] in
                guard let self else { return }
                let dest = self.directoryContents.url
                Task {
                    _ = try? await QuickActionService.shared.createPDF(from: [item.url], in: dest)
                    await MainActor.run {
                        self.directoryContents.reload()
                        self.reloadData()
                    }
                }
            },
            runShortcut: { [weak self] shortcutName in
                guard let self else { return }
                Task {
                    _ = try? await QuickActionService.shared.runShortcut(name: shortcutName, inputFile: item.url)
                    await MainActor.run {
                        self.directoryContents.reload()
                        self.reloadData()
                    }
                }
            },
            toggleTag: { [weak self] color in
                guard let self else { return }
                Task {
                    try? await TagService.shared.toggleColorTag(color, for: [item.url])
                    await MainActor.run {
                        self.directoryContents.reload()
                        self.reloadData()
                    }
                }
            },
            clearTags: { [weak self] in
                guard let self else { return }
                Task {
                    try? await TagService.shared.clearAllTags(for: [item.url])
                    await MainActor.run {
                        self.directoryContents.reload()
                        self.reloadData()
                    }
                }
            },
            copyChecksum: {
                guard !item.isDirectory else { return }
                Task {
                    if let hash = try? await ChecksumService.shared.computeSHA256(url: item.url) {
                        await MainActor.run {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(hash, forType: .string)
                        }
                    }
                }
            },
            findDuplicates: { [weak self] in
                guard let self else { return }
                let folder = item.isDirectory ? item.url : self.directoryContents.url
                self.onFindDuplicates?(folder)
            },
            gitStage: isGit ? { [weak self] in
                guard let self else { return }
                Task {
                    try? await GitService.shared.stage(urls: [item.url], at: self.directoryContents.url)
                    await MainActor.run {
                        self.directoryContents.reload()
                        self.reloadData()
                    }
                }
            } : nil,
            gitUnstage: isGit ? { [weak self] in
                guard let self else { return }
                Task {
                    try? await GitService.shared.unstage(urls: [item.url], at: self.directoryContents.url)
                    await MainActor.run {
                        self.directoryContents.reload()
                        self.reloadData()
                    }
                }
            } : nil,
            gitDiscard: isGit ? { [weak self] in
                guard let self else { return }
                Task {
                    try? await GitService.shared.discardChanges(for: item.url, at: self.directoryContents.url)
                    await MainActor.run {
                        self.directoryContents.reload()
                        self.reloadData()
                    }
                }
            } : nil,
            gitDiff: isGit ? { [weak self] in
                self?.onGitDiff?(item.url)
            } : nil,
            gitCommit: isGit ? { [weak self] in
                self?.onGitCommit?()
            } : nil
        )

        let menu = FileContextMenu.makeMenu(for: [item], actions: actions)
        NSMenu.popUpContextMenu(menu, with: event, for: splitContainer)
    }
}

// MARK: - Supporting Views

/// Filmstrip individual thumbnail item cell with icon, label, and selection indicator.
private final class GalleryThumbnailItemView: NSView {
    let item: FileItem
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    var isSelected: Bool = false {
        didSet {
            needsDisplay = true
        }
    }

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let cloudBadgeView = NSImageView()
    private let gitBadgeView = NSTextField(labelWithString: "")
    private let dotsView = NSImageView()

    init(item: FileItem) {
        self.item = item
        super.init(frame: .zero)
        wantsLayer = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = NSWorkspace.shared.icon(forFile: item.url.path)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)

        cloudBadgeView.translatesAutoresizingMaskIntoConstraints = false
        cloudBadgeView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(cloudBadgeView)

        gitBadgeView.translatesAutoresizingMaskIntoConstraints = false
        gitBadgeView.font = NSFont.systemFont(ofSize: 8, weight: .bold)
        gitBadgeView.alignment = .center
        gitBadgeView.wantsLayer = true
        gitBadgeView.layer?.cornerRadius = 6
        gitBadgeView.layer?.masksToBounds = true
        gitBadgeView.layer?.borderWidth = 0.5
        gitBadgeView.layer?.borderColor = NSColor.separatorColor.cgColor
        gitBadgeView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor
        addSubview(gitBadgeView)

        dotsView.translatesAutoresizingMaskIntoConstraints = false
        dotsView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(dotsView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = item.name
        titleLabel.font = NSFont.systemFont(ofSize: 10)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 48),
            imageView.heightAnchor.constraint(equalToConstant: 48),

            gitBadgeView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 3),
            gitBadgeView.topAnchor.constraint(equalTo: imageView.topAnchor, constant: -2),
            gitBadgeView.widthAnchor.constraint(equalToConstant: 14),
            gitBadgeView.heightAnchor.constraint(equalToConstant: 14),

            cloudBadgeView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 3),
            cloudBadgeView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 3),
            cloudBadgeView.widthAnchor.constraint(equalToConstant: 13),
            cloudBadgeView.heightAnchor.constraint(equalToConstant: 13),

            dotsView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: -2),
            dotsView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 2),
            dotsView.heightAnchor.constraint(equalToConstant: 8),

            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),
        ])

        if let gitStatus = item.gitStatus {
            gitBadgeView.stringValue = gitStatus.rawValue
            gitBadgeView.textColor = gitStatus.badgeColor
            gitBadgeView.toolTip = "Git: \(gitStatus.displayName)"
            gitBadgeView.isHidden = false
        } else {
            gitBadgeView.stringValue = ""
            gitBadgeView.isHidden = true
        }

        switch item.cloudStatus {
        case .onlineOnly:
            cloudBadgeView.image = NSImage(systemSymbolName: "icloud.and.arrow.down.fill", accessibilityDescription: "Stored in cloud")
            cloudBadgeView.contentTintColor = .secondaryLabelColor
            cloudBadgeView.isHidden = false
        case .downloading:
            cloudBadgeView.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Downloading")
            cloudBadgeView.contentTintColor = .systemBlue
            cloudBadgeView.isHidden = false
        case .conflict:
            cloudBadgeView.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Sync conflict")
            cloudBadgeView.contentTintColor = .systemOrange
            cloudBadgeView.isHidden = false
        case .downloaded, .notCloud:
            cloudBadgeView.image = nil
            cloudBadgeView.isHidden = true
        }

        if !item.tagColors.isEmpty {
            dotsView.image = TagDotsHelper.image(for: item.tagColors, diameter: 8)
            dotsView.isHidden = false
        } else {
            dotsView.image = nil
            dotsView.isHidden = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isSelected {
            let bgPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6)
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25).setFill()
            bgPath.fill()

            NSColor.selectedContentBackgroundColor.setStroke()
            bgPath.lineWidth = 1.5
            bgPath.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            onClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }
}

/// Fallback SwiftUI preview when a directory is selected in Gallery View.
private struct GalleryFolderView: View {
    let item: FileItem
    var onOpen: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.accentColor)
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)

            Text(item.name)
                .font(.title2)
                .fontWeight(.bold)
                .textSelection(.enabled)

            if let modDate = item.modificationDate {
                Text("Modified: \(modDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button("Open Folder", action: onOpen)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
