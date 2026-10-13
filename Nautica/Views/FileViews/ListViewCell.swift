import AppKit

/// View-based table cell for the list view. The Name column embeds an expandable
/// disclosure chevron, 16×16 `NSImageView` + `NSTextField`; the other columns are text-only.
/// The cell always contains these subviews and shows/hides the disclosure button and icon per column,
/// which keeps one reusable cell class for every column.
final class ListViewCell: NSTableCellView {
    static let iconSize: CGFloat = 16

    private(set) var fileItem: FileItem?
    private var iconHeightConstraint: NSLayoutConstraint!
    private var iconWidthConstraint: NSLayoutConstraint!
    private var gitBadgeLabel: NSTextField!
    private var cloudStatusImageView: NSImageView!
    private var tagDotsImageView: NSImageView!
    private var disclosureButton: NSButton!
    private var disclosureLeadingConstraint: NSLayoutConstraint!
    var onToggleExpand: (() -> Void)?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        let disclosure = NSButton()
        disclosure.isBordered = false
        disclosure.bezelStyle = .regularSquare
        disclosure.setButtonType(.momentaryChange)
        disclosure.imagePosition = .imageOnly
        disclosure.imageScaling = .scaleProportionallyUpOrDown
        disclosure.contentTintColor = .secondaryLabelColor
        disclosure.translatesAutoresizingMaskIntoConstraints = false
        disclosure.target = self
        disclosure.action = #selector(disclosureAction)
        self.disclosureButton = disclosure

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        self.imageView = imageView

        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        self.textField = label

        let dotsView = NSImageView()
        dotsView.imageScaling = .scaleProportionallyUpOrDown
        dotsView.translatesAutoresizingMaskIntoConstraints = false
        dotsView.isHidden = true
        self.tagDotsImageView = dotsView

        let gitBadge = NSTextField(labelWithString: "")
        gitBadge.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        gitBadge.alignment = .center
        gitBadge.translatesAutoresizingMaskIntoConstraints = false
        gitBadge.isHidden = true
        self.gitBadgeLabel = gitBadge

        let cloudView = NSImageView()
        cloudView.imageScaling = .scaleProportionallyUpOrDown
        cloudView.translatesAutoresizingMaskIntoConstraints = false
        cloudView.isHidden = true
        self.cloudStatusImageView = cloudView

        addSubview(disclosure)
        addSubview(imageView)
        addSubview(label)
        addSubview(dotsView)
        addSubview(gitBadge)
        addSubview(cloudView)

        // Text-only columns collapse the icon slot to zero width.
        iconWidthConstraint = imageView.widthAnchor.constraint(equalToConstant: Self.iconSize)
        iconHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: Self.iconSize)
        disclosureLeadingConstraint = disclosure.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2)

        NSLayoutConstraint.activate([
            disclosureLeadingConstraint,
            disclosure.centerYAnchor.constraint(equalTo: centerYAnchor),
            disclosure.widthAnchor.constraint(equalToConstant: 14),
            disclosure.heightAnchor.constraint(equalToConstant: 14),

            imageView.leadingAnchor.constraint(equalTo: disclosure.trailingAnchor, constant: 2),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint,
            iconHeightConstraint,

            cloudStatusImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            cloudStatusImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            cloudStatusImageView.widthAnchor.constraint(equalToConstant: 14),
            cloudStatusImageView.heightAnchor.constraint(equalToConstant: 14),

            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            dotsView.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            dotsView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotsView.heightAnchor.constraint(equalToConstant: 10),

            gitBadge.leadingAnchor.constraint(equalTo: dotsView.trailingAnchor, constant: 2),
            gitBadge.trailingAnchor.constraint(lessThanOrEqualTo: cloudStatusImageView.leadingAnchor, constant: -4),
            gitBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func disclosureAction() {
        onToggleExpand?()
    }

    /// Populates the cell for one column.
    func configure(
        with item: FileItem,
        forColumn column: ListColumn,
        depth: Int = 0,
        isExpanded: Bool = false,
        tags: String = "",
        fontSize: CGFloat = 13,
        iconSize: CGFloat = 16,
        onToggleExpand: (() -> Void)? = nil
    ) {
        fileItem = item
        self.onToggleExpand = onToggleExpand

        imageView?.isHidden = column != .name
        iconWidthConstraint.constant = column == .name ? iconSize : 0
        iconHeightConstraint.constant = iconSize
        textField?.font = NSFont.systemFont(ofSize: fontSize)
        textField?.alignment = column == .size ? .right : .left

        if column == .name {
            disclosureLeadingConstraint.constant = 2 + CGFloat(depth) * 16
            disclosureButton.isHidden = !item.isDirectory
            let chevronSymbol = isExpanded ? "chevron.down" : "chevron.right"
            disclosureButton.image = NSImage(systemSymbolName: chevronSymbol, accessibilityDescription: isExpanded ? "Collapse" : "Expand")

            switch item.cloudStatus {
            case .onlineOnly:
                cloudStatusImageView.image = NSImage(systemSymbolName: "icloud.and.arrow.down", accessibilityDescription: "Stored in cloud")
                cloudStatusImageView.contentTintColor = .secondaryLabelColor
                cloudStatusImageView.isHidden = false
            case .downloading:
                cloudStatusImageView.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Downloading")
                cloudStatusImageView.contentTintColor = .systemBlue
                cloudStatusImageView.isHidden = false
            case .conflict:
                cloudStatusImageView.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Sync conflict")
                cloudStatusImageView.contentTintColor = .systemOrange
                cloudStatusImageView.isHidden = false
            case .downloaded, .notCloud:
                cloudStatusImageView.isHidden = true
                cloudStatusImageView.image = nil
            }

            if !item.tagColors.isEmpty {
                tagDotsImageView.image = TagDotsHelper.image(for: item.tagColors, diameter: 8)
                tagDotsImageView.isHidden = false
            } else {
                tagDotsImageView.image = nil
                tagDotsImageView.isHidden = true
            }

            if let gitStatus = item.gitStatus {
                gitBadgeLabel.stringValue = gitStatus.rawValue
                gitBadgeLabel.textColor = gitStatus.badgeColor
                gitBadgeLabel.toolTip = "Git: \(gitStatus.displayName)"
                gitBadgeLabel.isHidden = false
            } else {
                gitBadgeLabel.stringValue = ""
                gitBadgeLabel.isHidden = true
            }
        } else {
            disclosureLeadingConstraint.constant = 2
            disclosureButton.isHidden = true
            cloudStatusImageView.isHidden = true
            cloudStatusImageView.image = nil
            tagDotsImageView.isHidden = true
            tagDotsImageView.image = nil
            gitBadgeLabel.stringValue = ""
            gitBadgeLabel.isHidden = true
        }

        switch column {
        case .name:
            imageView?.image = nil // assigned asynchronously by the controller
            textField?.stringValue = item.name
        case .size:
            if item.isDirectory {
                textField?.stringValue = "—"
            } else if let size = item.size {
                textField?.stringValue = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            } else {
                textField?.stringValue = "—"
            }
        case .modificationDate:
            textField?.stringValue = Self.dateString(item.modificationDate)
        case .creationDate:
            textField?.stringValue = Self.dateString(item.creationDate)
        case .kind:
            textField?.stringValue = item.kind
        case .tags:
            let tagNames = item.tagInfos.map(\.displayName)
            textField?.stringValue = tagNames.isEmpty ? tags : tagNames.joined(separator: ", ")
        }

        // VoiceOver Accessibility Configuration
        setAccessibilityElement(true)
        if column == .name {
            setAccessibilityRole(.cell)
            var a11yParts: [String] = [item.name, item.isDirectory ? "Folder" : "File"]
            if let gitStatus = item.gitStatus {
                a11yParts.append("Git \(gitStatus.displayName)")
            }
            if !item.tagColors.isEmpty {
                a11yParts.append("\(item.tagColors.count) tags")
            }
            if item.cloudStatus == .onlineOnly {
                a11yParts.append("Stored in cloud")
            }
            setAccessibilityLabel(a11yParts.joined(separator: ", "))
            setAccessibilityHelp(item.isDirectory ? (isExpanded ? "Expanded folder, tap to collapse" : "Collapsed folder, tap to expand") : "File")
        } else {
            setAccessibilityRole(.staticText)
            setAccessibilityLabel("\(column.headerTitle): \(textField?.stringValue ?? "empty")")
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        fileItem = nil
        onToggleExpand = nil
        imageView?.image = nil
        disclosureButton.isHidden = true
        cloudStatusImageView.isHidden = true
        cloudStatusImageView.image = nil
        tagDotsImageView.isHidden = true
        tagDotsImageView.image = nil
        gitBadgeLabel.stringValue = ""
        gitBadgeLabel.isHidden = true
    }

    /// White text on the selection highlight, label color otherwise.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            let isEmphasized = backgroundStyle == .emphasized
            textField?.textColor = isEmphasized
                ? .alternateSelectedControlTextColor
                : .labelColor
            disclosureButton.contentTintColor = isEmphasized
                ? .alternateSelectedControlTextColor
                : .secondaryLabelColor

            if isEmphasized {
                cloudStatusImageView.contentTintColor = .alternateSelectedControlTextColor
                gitBadgeLabel.textColor = .alternateSelectedControlTextColor
            } else {
                if let status = fileItem?.cloudStatus {
                    switch status {
                    case .onlineOnly: cloudStatusImageView.contentTintColor = .secondaryLabelColor
                    case .downloading: cloudStatusImageView.contentTintColor = .systemBlue
                    case .conflict: cloudStatusImageView.contentTintColor = .systemOrange
                    default: break
                    }
                }
                if let gitStatus = fileItem?.gitStatus {
                    gitBadgeLabel.textColor = gitStatus.badgeColor
                }
            }
        }
    }

    /// Relative ("3 hours ago") within the last 24 hours, absolute otherwise.
    private static func dateString(_ date: Date?) -> String {
        guard let date else { return "—" }
        if abs(date.timeIntervalSinceNow) < 24 * 60 * 60 {
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        return absoluteFormatter.string(from: date)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
