import AppKit
import Foundation

/// Tracks selected items (multi-select with Cmd/Shift), Finder/Nemo semantics.
@Observable
final class SelectionModel {
    var selectedIDs: Set<UUID> = []
    /// Anchor for Shift-range selection.
    var anchorID: UUID?
    var lastClickedID: UUID?

    /// Plain- or Cmd-click. Shift-click must go through `handleClick(_:modifierFlags:in:)`
    /// because ranges require the item list.
    func select(_ id: UUID, modifierFlags: NSEvent.ModifierFlags) {
        if modifierFlags.contains(.command) {
            // Cmd-click: toggle the item in the selection.
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
        } else {
            // Plain click: select only this item.
            selectedIDs = [id]
        }
        lastClickedID = id
        anchorID = id
    }

    /// Unified click entry point used by the file views.
    func handleClick(_ id: UUID, modifierFlags: NSEvent.ModifierFlags, in items: [FileItem]) {
        if modifierFlags.contains(.shift) {
            let start = anchorID ?? lastClickedID ?? items.first?.id
            if let start {
                selectRange(from: start, to: id, in: items)
                lastClickedID = id
            } else {
                select(id, modifierFlags: [])
            }
        } else {
            select(id, modifierFlags: modifierFlags)
        }
    }

    /// Selects the contiguous range between two items, replacing the selection.
    /// Order-independent: `from` may be after `to`.
    func selectRange(from: UUID, to: UUID, in items: [FileItem]) {
        guard let fromIndex = items.firstIndex(where: { $0.id == from }),
              let toIndex = items.firstIndex(where: { $0.id == to }) else { return }
        let range = min(fromIndex, toIndex)...max(fromIndex, toIndex)
        selectedIDs = Set(items[range].map(\.id))
    }

    func selectAll(in items: [FileItem]) {
        selectedIDs = Set(items.map(\.id))
    }

    func deselectAll() {
        selectedIDs.removeAll()
        anchorID = nil
        lastClickedID = nil
    }

    func invertSelection(in items: [FileItem]) {
        let all = Set(items.map(\.id))
        selectedIDs = all.subtracting(selectedIDs)
    }

    func isSelected(_ id: UUID) -> Bool {
        selectedIDs.contains(id)
    }

    // MARK: - Keyboard navigation

    /// Moves the selection by `delta` positions in the given ordering.
    /// With Shift held, extends the range from the anchor instead.
    func moveSelection(by delta: Int, in items: [FileItem], extending: Bool) {
        guard !items.isEmpty else { return }

        let currentIndex: Int?
        if let lastClickedID {
            currentIndex = items.firstIndex(where: { $0.id == lastClickedID })
        } else {
            currentIndex = nil
        }

        let nextIndex: Int
        if let currentIndex {
            nextIndex = max(0, min(items.count - 1, currentIndex + delta))
        } else {
            nextIndex = delta < 0 ? items.count - 1 : 0
        }
        let nextID = items[nextIndex].id

        if extending {
            let start = anchorID ?? items[currentIndex ?? (delta < 0 ? items.count - 1 : 0)].id
            selectRange(from: start, to: nextID, in: items)
            lastClickedID = nextID
        } else {
            selectedIDs = [nextID]
            anchorID = nextID
            lastClickedID = nextID
        }
    }

    /// Selects the first or last item (Home/End); Shift extends from the anchor.
    func selectBoundary(first: Bool, in items: [FileItem], extending: Bool) {
        guard let target = first ? items.first : items.last else { return }
        if extending {
            let start = anchorID ?? lastClickedID ?? target.id
            selectRange(from: start, to: target.id, in: items)
            lastClickedID = target.id
        } else {
            selectedIDs = [target.id]
            anchorID = target.id
            lastClickedID = target.id
        }
    }
}

/// Buffers rapid keystrokes (within 500ms) for type-ahead selection.
struct TypeAheadBuffer {
    static let timeout: TimeInterval = 0.5

    private(set) var buffer = ""
    private var lastKeystroke = Date.distantPast

    mutating func append(_ character: Character, at date: Date = .now) {
        if date.timeIntervalSince(lastKeystroke) > Self.timeout {
            buffer = ""
        }
        buffer.append(character)
        lastKeystroke = date
    }

    mutating func reset() {
        buffer = ""
    }

    /// First item whose name starts with the buffer (case-insensitive).
    func match(in items: [FileItem]) -> FileItem? {
        guard !buffer.isEmpty else { return nil }
        let needle = buffer.lowercased()
        return items.first { $0.name.lowercased().hasPrefix(needle) }
    }
}
