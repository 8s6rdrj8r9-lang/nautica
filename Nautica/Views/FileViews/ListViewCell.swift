import AppKit

/// View-based table cell for the list view. The Name column embeds a 16×16
/// `NSImageView` + `NSTextField`; the other columns are text-only. The cell
/// always contains both subviews and shows/hides the icon per column, which
/// keeps one reusable cell class for every column.
final class ListViewCell: NSTableCellView {
    static let iconSize: CGFloat = 16

    private(set) var fileItem: FileItem?
    private var iconWidthConstraint: NSLayoutConstraint!

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

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

        addSubview(imageView)
        addSubview(label)

        // Text-only columns collapse the icon slot to zero width.
        iconWidthConstraint = imageView.widthAnchor.constraint(equalToConstant: Self.iconSize)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint,
            imageView.heightAnchor.constraint(equalToConstant: Self.iconSize),

            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Populates the cell for one column. `tags` is the seam for the
    /// TagService integration arriving in Prompt 11 (F-013); for now the
    /// caller passes an empty string. Folder sizes show "—" because
    /// enumerating folder contents per row would be too costly.
    func configure(with item: FileItem, forColumn column: ListColumn, tags: String = "") {
        fileItem = item
        imageView?.isHidden = column != .name
        iconWidthConstraint.constant = column == .name ? Self.iconSize : 0
        textField?.alignment = column == .size ? .right : .left

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
            textField?.stringValue = tags
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        fileItem = nil
        imageView?.image = nil
    }

    /// White text on the selection highlight, label color otherwise.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            textField?.textColor = backgroundStyle == .emphasized
                ? .alternateSelectedControlTextColor
                : .labelColor
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
