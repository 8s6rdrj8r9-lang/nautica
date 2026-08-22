import AppKit
import Foundation

/// Representation of a file or folder in the file system.
struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let modificationDate: Date?
    let creationDate: Date?
    let isHidden: Bool
    let kind: String

    /// Lazily-loaded file icon (system icon for the file's type).
    var iconImage: NSImage? {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}
