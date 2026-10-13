import AppKit

/// Collection view item for the icon grid: icon on top, filename below,
/// rounded-rect selection highlight. Built entirely in code (no XIB).
final class IconViewItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("IconViewItem")

    var iconView: NSImageView!
    var nameLabel: NSTextField!
    var cloudBadgeView: NSImageView!
    var tagDotsView: NSImageView!
    var gitBadgeView: NSTextField!
    private var iconWidth: NSLayoutConstraint!
    private var iconHeight: NSLayoutConstraint!
    private(set) var fileItem: FileItem?

    /// Rounded-rect highlight shown behind the icon and label when selected.
    private let highlightView = NSView()

    override var isSelected: Bool {
        didSet { updateHighlight() }
    }

    override func loadView() {
        let container = NSView()
        view = container

        highlightView.wantsLayer = true
        highlightView.layer?.cornerRadius = 8
        highlightView.isHidden = true
        highlightView.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.translatesAutoresizingMaskIntoConstraints = false
        iconView = imageView

        let badgeView = NSImageView()
        badgeView.imageScaling = .scaleProportionallyUpOrDown
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.wantsLayer = true
        badgeView.layer?.cornerRadius = 9
        badgeView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor
        badgeView.layer?.borderWidth = 0.5
        badgeView.layer?.borderColor = NSColor.separatorColor.cgColor
        badgeView.isHidden = true
        cloudBadgeView = badgeView

        let gitBadge = NSTextField(labelWithString: "")
        gitBadge.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        gitBadge.alignment = .center
        gitBadge.wantsLayer = true
        gitBadge.layer?.cornerRadius = 8
        gitBadge.layer?.masksToBounds = true
        gitBadge.layer?.borderWidth = 0.5
        gitBadge.layer?.borderColor = NSColor.separatorColor.cgColor
        gitBadge.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor
        gitBadge.translatesAutoresizingMaskIntoConstraints = false
        gitBadge.isHidden = true
        gitBadgeView = gitBadge

        let dotsView = NSImageView()
        dotsView.imageScaling = .scaleProportionallyUpOrDown
        dotsView.translatesAutoresizingMaskIntoConstraints = false
        dotsView.isHidden = true
        tagDotsView = dotsView

        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 2
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        nameLabel = label

        container.addSubview(highlightView)
        container.addSubview(imageView)
        container.addSubview(badgeView)
        container.addSubview(gitBadge)
        container.addSubview(dotsView)
        container.addSubview(label)

        iconWidth = imageView.widthAnchor.constraint(equalToConstant: 64)
        iconHeight = imageView.heightAnchor.constraint(equalToConstant: 64)
        NSLayoutConstraint.activate([
            iconWidth, iconHeight,
            highlightView.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            highlightView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            highlightView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
            highlightView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),

            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            gitBadge.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
            gitBadge.topAnchor.constraint(equalTo: imageView.topAnchor, constant: -2),
            gitBadge.widthAnchor.constraint(equalToConstant: 16),
            gitBadge.heightAnchor.constraint(equalToConstant: 16),

            badgeView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
            badgeView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 2),
            badgeView.widthAnchor.constraint(equalToConstant: 18),
            badgeView.heightAnchor.constraint(equalToConstant: 18),

            dotsView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: -2),
            dotsView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 2),
            dotsView.heightAnchor.constraint(equalToConstant: 12),

            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            label.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -4),
        ])
    }

    /// Populates the cell; the icon image is assigned asynchronously by the controller.
    func configure(with item: FileItem, isSelected: Bool, fontSize: CGFloat = 11, iconSize: CGFloat = 64) {
        loadViewIfNeeded() // the collection view loads item views lazily
        nameLabel.font = NSFont.systemFont(ofSize: fontSize)
        iconWidth.constant = iconSize
        iconHeight.constant = iconSize
        fileItem = item
        nameLabel.stringValue = item.name
        nameLabel.toolTip = item.name
        iconView.image = nil
        self.isSelected = isSelected

        if let gitStatus = item.gitStatus {
            gitBadgeView.stringValue = gitStatus.rawValue
            gitBadgeView.textColor = gitStatus.badgeColor
            gitBadgeView.toolTip = "Git: \(gitStatus.displayName)"
            gitBadgeView.isHidden = false
        } else {
            gitBadgeView.stringValue = ""
            gitBadgeView.isHidden = true
        }

        if !item.tagColors.isEmpty {
            tagDotsView.image = TagDotsHelper.image(for: item.tagColors, diameter: 10)
            tagDotsView.isHidden = false
        } else {
            tagDotsView.image = nil
            tagDotsView.isHidden = true
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
            cloudBadgeView.isHidden = true
            cloudBadgeView.image = nil
        }

        // VoiceOver Accessibility Configuration
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        var a11yParts: [String] = [item.name, item.isDirectory ? "Folder" : "File", item.formattedSize]
        if let gitStatus = item.gitStatus {
            a11yParts.append("Git \(gitStatus.displayName)")
        }
        if !item.tagColors.isEmpty {
            a11yParts.append("\(item.tagColors.count) tags")
        }
        if item.cloudStatus == .onlineOnly {
            a11yParts.append("Stored in cloud")
        }
        view.setAccessibilityLabel(a11yParts.joined(separator: ", "))
        view.setAccessibilityHelp("Double-click to open, Space for Quick Look")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        fileItem = nil
        iconView.image = nil
        gitBadgeView.stringValue = ""
        gitBadgeView.isHidden = true
        cloudBadgeView.isHidden = true
        cloudBadgeView.image = nil
        tagDotsView.isHidden = true
        tagDotsView.image = nil
        isSelected = false
    }

    private func updateHighlight() {
        guard isViewLoaded else { return }
        if isSelected {
            highlightView.layer?.backgroundColor = NSColor.selectedContentBackgroundColor.cgColor
            highlightView.layer?.borderColor = NSColor.selectedContentBackgroundColor
                .shadow(withLevel: 0.3)?.cgColor
            highlightView.layer?.borderWidth = 1
            highlightView.isHidden = false
            nameLabel.textColor = .white
        } else {
            highlightView.isHidden = true
            nameLabel.textColor = .labelColor
        }
    }
}
