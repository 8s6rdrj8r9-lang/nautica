import Foundation

extension URL {
    /// Returns a URL for this item's name inside `directory`, appending
    /// " 1", " 2", … before the extension until the name doesn't collide
    /// (Finder-style "name 1.ext"). Used by copy/move in Prompt 10.
    func nonCollidingURL(in directory: URL) -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent(lastPathComponent)
        // attributesOfItem inspects the link itself, so dangling symlinks count as collisions.
        guard (try? fileManager.attributesOfItem(atPath: candidate.path)) != nil else { return candidate }

        let base = deletingPathExtension().lastPathComponent
        let pathExtension = self.pathExtension
        var counter = 1
        while true {
            let name = pathExtension.isEmpty
                ? "\(base) \(counter)"
                : "\(base) \(counter).\(pathExtension)"
            candidate = directory.appendingPathComponent(name)
            if (try? fileManager.attributesOfItem(atPath: candidate.path)) == nil { return candidate }
            counter += 1
        }
    }
}
