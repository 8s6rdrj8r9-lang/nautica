import AppKit
import Foundation
import Observation

/// A single collision between an incoming item and an item already present in the destination.
struct FileConflict: Identifiable, Sendable {
    var id: String { sourceURL.path }

    let sourceURL: URL
    let destinationURL: URL
    let fileName: String
    let sourceDate: Date?
    let sourceSize: Int64?
    let destinationDate: Date?
    let destinationSize: Int64?
    let isDirectory: Bool

    init(sourceURL: URL, destinationURL: URL) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.fileName = sourceURL.lastPathComponent

        let fm = FileManager.default
        let srcAttrs = try? fm.attributesOfItem(atPath: sourceURL.path)
        self.sourceDate = srcAttrs?[.modificationDate] as? Date
        self.sourceSize = srcAttrs?[.size] as? Int64

        let dstAttrs = try? fm.attributesOfItem(atPath: destinationURL.path)
        self.destinationDate = dstAttrs?[.modificationDate] as? Date
        self.destinationSize = dstAttrs?[.size] as? Int64

        var isDir: ObjCBool = false
        fm.fileExists(atPath: sourceURL.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
    }
}

/// User's resolution for a file conflict.
enum ConflictResolutionChoice: Sendable {
    case keepBoth
    case replace
    case stop
}

/// Manages multi-item conflict resolution state and user choices.
@Observable
final class ConflictResolutionModel {
    let conflicts: [FileConflict]
    let isMove: Bool
    let destination: URL

    var currentIndex: Int = 0
    var applyToAll: Bool = false
    var resolutions: [URL: ConflictResolutionChoice] = [:]
    var isFinished: Bool = false

    var currentConflict: FileConflict? {
        guard currentIndex < conflicts.count else { return nil }
        return conflicts[currentIndex]
    }

    var remainingCount: Int {
        max(0, conflicts.count - currentIndex)
    }

    init(conflicts: [FileConflict], isMove: Bool, destination: URL) {
        self.conflicts = conflicts
        self.isMove = isMove
        self.destination = destination
    }

    func resolveCurrent(with choice: ConflictChoice) {
        guard let current = currentConflict else { return }

        let resolution: ConflictResolutionChoice
        switch choice {
        case .keepBoth: resolution = .keepBoth
        case .replace: resolution = .replace
        case .stop: resolution = .stop
        }

        if choice == .stop {
            resolutions[current.sourceURL] = .stop
            isFinished = true
            return
        }

        if applyToAll {
            for i in currentIndex..<conflicts.count {
                resolutions[conflicts[i].sourceURL] = resolution
            }
            isFinished = true
        } else {
            resolutions[current.sourceURL] = resolution
            currentIndex += 1
            if currentIndex >= conflicts.count {
                isFinished = true
            }
        }
    }

    enum ConflictChoice {
        case keepBoth
        case replace
        case stop
    }
}
