import Foundation
import UniformTypeIdentifiers

/// Structured group containing a section title and the corresponding items.
struct FileItemGroup: Identifiable, Equatable {
    let title: String
    let items: [FileItem]

    var id: String { title }
}

/// Categorizes files into ordered, logical sections for "Group By / Arrange By".
enum GroupClassifier {

    static func classify(_ items: [FileItem], by criterion: GroupByCriterion) -> [FileItemGroup] {
        guard criterion != .none, !items.isEmpty else {
            return [FileItemGroup(title: "", items: items)]
        }

        switch criterion {
        case .none:
            return [FileItemGroup(title: "", items: items)]

        case .kind:
            return classifyByKind(items)

        case .dateModified:
            return classifyByDate(items, dateKey: \.modificationDate)

        case .dateCreated:
            return classifyByDate(items, dateKey: \.creationDate)

        case .size:
            return classifyBySize(items)

        case .tags:
            return [FileItemGroup(title: "All Items", items: items)]
        }
    }

    // MARK: - Kind Classification

    private static let kindOrder = [
        "Folders",
        "Applications",
        "Images",
        "PDF Documents",
        "Documents & Text",
        "Audio & Music",
        "Videos & Movies",
        "Code & Developer",
        "Archives",
        "Other"
    ]

    private static func classifyByKind(_ items: [FileItem]) -> [FileItemGroup] {
        var buckets: [String: [FileItem]] = [:]

        for item in items {
            let category: String
            if item.isDirectory {
                if item.url.pathExtension.lowercased() == "app" {
                    category = "Applications"
                } else {
                    category = "Folders"
                }
            } else {
                let ext = item.url.pathExtension.lowercased()
                switch ext {
                case "png", "jpg", "jpeg", "gif", "webp", "tiff", "heic", "svg", "icns":
                    category = "Images"
                case "pdf":
                    category = "PDF Documents"
                case "txt", "md", "markdown", "rtf", "doc", "docx", "pages", "csv", "json", "xml", "yaml", "yml", "log":
                    category = "Documents & Text"
                case "mp3", "m4a", "wav", "flac", "aac", "aiff", "ogg":
                    category = "Audio & Music"
                case "mp4", "mov", "mkv", "avi", "webm", "m4v":
                    category = "Videos & Movies"
                case "swift", "c", "cpp", "h", "m", "mm", "py", "js", "ts", "html", "css", "sh", "zsh", "go", "rs", "java", "rb", "php":
                    category = "Code & Developer"
                case "zip", "tar", "gz", "7z", "rar", "dmg", "pkg", "iso":
                    category = "Archives"
                default:
                    category = "Other"
                }
            }
            buckets[category, default: []].append(item)
        }

        return kindOrder.compactMap { name in
            guard let groupItems = buckets[name], !groupItems.isEmpty else { return nil }
            return FileItemGroup(title: name, items: groupItems)
        }
    }

    // MARK: - Date Classification

    private static let dateOrder = [
        "Today",
        "Yesterday",
        "Previous 7 Days",
        "Previous 30 Days",
        "Earlier This Year",
        "Previous Years",
        "No Date"
    ]

    private static func classifyByDate(_ items: [FileItem], dateKey: KeyPath<FileItem, Date?>) -> [FileItemGroup] {
        let calendar = Calendar.current
        let now = Date()
        var buckets: [String: [FileItem]] = [:]

        for item in items {
            guard let date = item[keyPath: dateKey] else {
                buckets["No Date", default: []].append(item)
                continue
            }

            let category: String
            if calendar.isDateInToday(date) {
                category = "Today"
            } else if calendar.isDateInYesterday(date) {
                category = "Yesterday"
            } else if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 7 {
                category = "Previous 7 Days"
            } else if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 30 {
                category = "Previous 30 Days"
            } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
                category = "Earlier This Year"
            } else {
                category = "Previous Years"
            }
            buckets[category, default: []].append(item)
        }

        return dateOrder.compactMap { name in
            guard let groupItems = buckets[name], !groupItems.isEmpty else { return nil }
            return FileItemGroup(title: name, items: groupItems)
        }
    }

    // MARK: - Size Classification

    private static let sizeOrder = [
        "Huge (> 1 GB)",
        "Large (100 MB – 1 GB)",
        "Medium (1 MB – 100 MB)",
        "Small (10 KB – 1 MB)",
        "Micro (< 10 KB)",
        "Zero KB",
        "Folders"
    ]

    private static func classifyBySize(_ items: [FileItem]) -> [FileItemGroup] {
        var buckets: [String: [FileItem]] = [:]

        for item in items {
            if item.isDirectory {
                buckets["Folders", default: []].append(item)
                continue
            }

            guard let bytes = item.size else {
                buckets["Zero KB", default: []].append(item)
                continue
            }

            let category: String
            if bytes >= 1_000_000_000 {
                category = "Huge (> 1 GB)"
            } else if bytes >= 100_000_000 {
                category = "Large (100 MB – 1 GB)"
            } else if bytes >= 1_000_000 {
                category = "Medium (1 MB – 100 MB)"
            } else if bytes >= 10_000 {
                category = "Small (10 KB – 1 MB)"
            } else if bytes > 0 {
                category = "Micro (< 10 KB)"
            } else {
                category = "Zero KB"
            }
            buckets[category, default: []].append(item)
        }

        return sizeOrder.compactMap { name in
            guard let groupItems = buckets[name], !groupItems.isEmpty else { return nil }
            return FileItemGroup(title: name, items: groupItems)
        }
    }
}
