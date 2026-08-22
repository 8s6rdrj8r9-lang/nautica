import Foundation

extension URL {
    /// Returns a URL for this item's name inside `directory`, appending
    /// " 1", " 2", … before the extension until the name doesn't collide
    /// (Finder-style "name 1.ext"). Used by copy/move in Prompt 10.
    func nonCollidingURL(in directory: URL) -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent(lastPathComponent)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let base = deletingPathExtension().lastPathComponent
        let pathExtension = self.pathExtension
        var counter = 1
        while true {
            let name = pathExtension.isEmpty
                ? "\(base) \(counter)"
                : "\(base) \(counter).\(pathExtension)"
            candidate = directory.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }
}
