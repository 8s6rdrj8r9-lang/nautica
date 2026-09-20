import Foundation

/// Supported attributes for Smart Folder search criteria.
enum SearchCriterionAttribute: String, CaseIterable, Identifiable {
    case kind = "Kind"
    case dateModified = "Date Modified"
    case dateCreated = "Date Created"
    case fileSize = "File Size"
    case name = "Name"
    case tags = "Tags"

    var id: String { rawValue }
}

/// Content kind filter options.
enum KindOption: String, CaseIterable, Identifiable {
    case any = "Any"
    case image = "Images"
    case document = "Documents"
    case pdf = "PDFs"
    case audio = "Audio"
    case movie = "Video"
    case archive = "Archives"
    case folder = "Folders"
    case application = "Applications"

    var id: String { rawValue }
}

/// Date range filter options.
enum DateOption: String, CaseIterable, Identifiable {
    case today = "Today"
    case within7Days = "Within last 7 days"
    case within30Days = "Within last 30 days"
    case within365Days = "Within last year"

    var id: String { rawValue }
}

/// Comparison operators for file size.
enum SizeComparison: String, CaseIterable, Identifiable {
    case greaterThan = "is greater than"
    case lessThan = "is less than"
    case equals = "equals"

    var id: String { rawValue }
}

/// Units of measure for file size criteria.
enum SizeUnit: String, CaseIterable, Identifiable {
    case kb = "KB"
    case mb = "MB"
    case gb = "GB"

    var id: String { rawValue }

    var bytesMultiplier: Int64 {
        switch self {
        case .kb: return 1_024
        case .mb: return 1_048_576
        case .gb: return 1_073_741_824
        }
    }
}

/// String comparison operators for name criteria.
enum NameComparison: String, CaseIterable, Identifiable {
    case contains = "contains"
    case beginsWith = "begins with"
    case endsWith = "ends with"
    case isEqual = "is"

    var id: String { rawValue }
}

/// An individual filter rule in the Smart Folder criteria builder.
struct SearchCriterion: Identifiable, Equatable {
    let id: UUID
    var attribute: SearchCriterionAttribute

    // Options for Kind
    var kind: KindOption

    // Options for Date
    var dateOption: DateOption

    // Options for Size
    var sizeComparison: SizeComparison
    var sizeValue: Double
    var sizeUnit: SizeUnit

    // Options for Name
    var nameComparison: NameComparison
    var textValue: String

    // Options for Tags
    var tagValue: String

    init(
        id: UUID = UUID(),
        attribute: SearchCriterionAttribute = .kind,
        kind: KindOption = .document,
        dateOption: DateOption = .within7Days,
        sizeComparison: SizeComparison = .greaterThan,
        sizeValue: Double = 10,
        sizeUnit: SizeUnit = .mb,
        nameComparison: NameComparison = .contains,
        textValue: String = "",
        tagValue: String = ""
    ) {
        self.id = id
        self.attribute = attribute
        self.kind = kind
        self.dateOption = dateOption
        self.sizeComparison = sizeComparison
        self.sizeValue = sizeValue
        self.sizeUnit = sizeUnit
        self.nameComparison = nameComparison
        self.textValue = textValue
        self.tagValue = tagValue
    }

    /// Converts this criterion into an `NSPredicate` usable by `NSMetadataQuery`.
    func toPredicate() -> NSPredicate {
        switch attribute {
        case .kind:
            switch kind {
            case .any:
                return NSPredicate(value: true)
            case .image:
                return NSPredicate(format: "%K ==[cd] 'public.image'", "kMDItemContentTypeTree")
            case .document:
                return NSPredicate(
                    format: "(%K ==[cd] 'public.content') OR (%K ==[cd] 'public.text') OR (%K ==[cd] 'com.adobe.pdf')",
                    "kMDItemContentTypeTree", "kMDItemContentTypeTree", "kMDItemContentTypeTree"
                )
            case .pdf:
                return NSPredicate(format: "%K ==[cd] 'com.adobe.pdf'", "kMDItemContentTypeTree")
            case .audio:
                return NSPredicate(format: "%K ==[cd] 'public.audio'", "kMDItemContentTypeTree")
            case .movie:
                return NSPredicate(
                    format: "(%K ==[cd] 'public.movie') OR (%K ==[cd] 'public.video')",
                    "kMDItemContentTypeTree", "kMDItemContentTypeTree"
                )
            case .archive:
                return NSPredicate(
                    format: "(%K ==[cd] 'public.archive') OR (%K ==[cd] 'com.apple.bom-compressed-cpio')",
                    "kMDItemContentTypeTree", "kMDItemContentTypeTree"
                )
            case .folder:
                return NSPredicate(format: "%K ==[cd] 'public.folder'", "kMDItemContentTypeTree")
            case .application:
                return NSPredicate(format: "%K ==[cd] 'com.apple.application'", "kMDItemContentTypeTree")
            }

        case .dateModified, .dateCreated:
            let key = attribute == .dateModified ? "kMDItemContentModificationDate" : "kMDItemFSCreationDate"
            let now = Date()
            let cutoffDate: Date
            switch dateOption {
            case .today:
                cutoffDate = Calendar.current.startOfDay(for: now)
            case .within7Days:
                cutoffDate = now.addingTimeInterval(-7 * 86_400)
            case .within30Days:
                cutoffDate = now.addingTimeInterval(-30 * 86_400)
            case .within365Days:
                cutoffDate = now.addingTimeInterval(-365 * 86_400)
            }
            return NSPredicate(format: "%K >= %@", key, cutoffDate as NSDate)

        case .fileSize:
            let bytes = Int64(sizeValue * Double(sizeUnit.bytesMultiplier))
            switch sizeComparison {
            case .greaterThan:
                return NSPredicate(format: "%K > %lld", "kMDItemFSSize", bytes)
            case .lessThan:
                return NSPredicate(format: "%K < %lld", "kMDItemFSSize", bytes)
            case .equals:
                return NSPredicate(format: "%K == %lld", "kMDItemFSSize", bytes)
            }

        case .name:
            guard !textValue.trimmingCharacters(in: .whitespaces).isEmpty else {
                return NSPredicate(value: true)
            }
            let sanitized = textValue.trimmingCharacters(in: .whitespaces)
            switch nameComparison {
            case .contains:
                return NSPredicate(format: "%K LIKE[cd] %@", "kMDItemFSName", "*\(sanitized)*")
            case .beginsWith:
                return NSPredicate(format: "%K LIKE[cd] %@", "kMDItemFSName", "\(sanitized)*")
            case .endsWith:
                return NSPredicate(format: "%K LIKE[cd] %@", "kMDItemFSName", "*\(sanitized)")
            case .isEqual:
                return NSPredicate(format: "%K ==[cd] %@", "kMDItemFSName", sanitized)
            }

        case .tags:
            guard !tagValue.trimmingCharacters(in: .whitespaces).isEmpty else {
                return NSPredicate(value: true)
            }
            let sanitized = tagValue.trimmingCharacters(in: .whitespaces)
            return NSPredicate(format: "%K LIKE[cd] %@", "kMDItemUserTags", "*\(sanitized)*")
        }
    }

    /// Converts this criterion into a raw query string suitable for `.savedSearch` property lists.
    func toRawQuery() -> String {
        switch attribute {
        case .kind:
            switch kind {
            case .any:
                return "true"
            case .image:
                return "kMDItemContentTypeTree = 'public.image'cd"
            case .document:
                return "(kMDItemContentTypeTree = 'public.content'cd || kMDItemContentTypeTree = 'public.text'cd || kMDItemContentTypeTree = 'com.adobe.pdf'cd)"
            case .pdf:
                return "kMDItemContentTypeTree = 'com.adobe.pdf'cd"
            case .audio:
                return "kMDItemContentTypeTree = 'public.audio'cd"
            case .movie:
                return "(kMDItemContentTypeTree = 'public.movie'cd || kMDItemContentTypeTree = 'public.video'cd)"
            case .archive:
                return "(kMDItemContentTypeTree = 'public.archive'cd || kMDItemContentTypeTree = 'com.apple.bom-compressed-cpio'cd)"
            case .folder:
                return "kMDItemContentTypeTree = 'public.folder'cd"
            case .application:
                return "kMDItemContentTypeTree = 'com.apple.application'cd"
            }

        case .dateModified, .dateCreated:
            let key = attribute == .dateModified ? "kMDItemContentModificationDate" : "kMDItemFSCreationDate"
            switch dateOption {
            case .today:
                return "\(key) >= $time.today()"
            case .within7Days:
                return "\(key) >= $time.today(-7)"
            case .within30Days:
                return "\(key) >= $time.today(-30)"
            case .within365Days:
                return "\(key) >= $time.today(-365)"
            }

        case .fileSize:
            let bytes = Int64(sizeValue * Double(sizeUnit.bytesMultiplier))
            switch sizeComparison {
            case .greaterThan:
                return "kMDItemFSSize > \(bytes)"
            case .lessThan:
                return "kMDItemFSSize < \(bytes)"
            case .equals:
                return "kMDItemFSSize == \(bytes)"
            }

        case .name:
            guard !textValue.trimmingCharacters(in: .whitespaces).isEmpty else { return "true" }
            let sanitized = textValue.trimmingCharacters(in: .whitespaces)
            switch nameComparison {
            case .contains:
                return "kMDItemFSName == '*\(sanitized)*'cd"
            case .beginsWith:
                return "kMDItemFSName == '\(sanitized)*'cd"
            case .endsWith:
                return "kMDItemFSName == '*\(sanitized)'cd"
            case .isEqual:
                return "kMDItemFSName == '\(sanitized)'cd"
            }

        case .tags:
            guard !tagValue.trimmingCharacters(in: .whitespaces).isEmpty else { return "true" }
            let sanitized = tagValue.trimmingCharacters(in: .whitespaces)
            return "kMDItemUserTags == '*\(sanitized)*'cd"
        }
    }
}
