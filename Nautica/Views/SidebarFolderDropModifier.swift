import SwiftUI
import AppKit

/// Enables dropping files/folders onto a sidebar or tree row, routing through
/// `FileOperationService` (or BrowserView callbacks) with Command-move support,
/// spring-loaded folder navigation on hover, and Finder-like visual focus when targeted.
struct SidebarFolderDropModifier: ViewModifier {
    let targetURL: URL
    var isInFavorites: Bool = false
    var onAddToFavorites: (([URL]) -> Void)? = nil
    var onPerformCopy: (([URL], URL) -> Void)? = nil
    var onPerformMove: (([URL], URL) -> Void)? = nil
    var onSpringLoad: ((URL) -> Void)? = nil

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .dropDestination(for: URL.self) { urls, _ in
                SpringLoadManager.shared.cancel()
                guard !urls.isEmpty else { return false }
                let commandHeld = NSEvent.modifierFlags.contains(.command)
                let allDirectories = urls.allSatisfy { url in
                    var isDir: ObjCBool = false
                    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
                }

                if isInFavorites && allDirectories && !commandHeld, let onAddToFavorites {
                    onAddToFavorites(urls)
                    return true
                }

                let move = commandHeld
                if move, let onPerformMove {
                    onPerformMove(urls, targetURL)
                } else if !move, let onPerformCopy {
                    onPerformCopy(urls, targetURL)
                } else {
                    Task {
                        let progress = Progress()
                        if move {
                            _ = await FileOperationService.shared.moveItems(urls, to: targetURL, progress: progress)
                        } else {
                            _ = await FileOperationService.shared.copyItems(urls, to: targetURL, progress: progress)
                        }
                    }
                }
                return true
            } isTargeted: { targeted in
                isTargeted = targeted
                if targeted {
                    SpringLoadManager.shared.hover(on: targetURL) { url in
                        onSpringLoad?(url)
                    }
                } else {
                    SpringLoadManager.shared.cancel()
                }
            }
    }
}
