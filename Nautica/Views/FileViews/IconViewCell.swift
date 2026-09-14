import AppKit

/// Collection view item for the icon grid: icon on top, filename below,
/// rounded-rect selection highlight. Built entirely in code (no XIB).
final class IconViewItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("IconViewItem")

    var iconView: NSImageView!
    var nameLabel: NSTextField!
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
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        fileItem = nil
        iconView.image = nil
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
