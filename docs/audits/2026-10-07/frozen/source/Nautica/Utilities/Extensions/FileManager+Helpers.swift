import Foundation

extension FileManager {
    var desktopURL: URL {
        urls(for: .desktopDirectory, in: .userDomainMask).first!
    }

    var homeURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    var downloadsURL: URL {
        urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }

    /// True if the file's name starts with "." or it carries the hidden resource key.
    func isHiddenFile(at url: URL) -> Bool {
        if url.lastPathComponent.hasPrefix(".") { return true }
        return (try? url.resourceValues(forKeys: [.isHiddenKey]).isHidden) ?? false
    }
}
