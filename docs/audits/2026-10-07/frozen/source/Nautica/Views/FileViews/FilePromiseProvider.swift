import AppKit
import Foundation
import UniformTypeIdentifiers

/// NSFilePromiseProvider that retains its own delegate (the provider's
/// delegate property semantics are left unspecified, so we keep it strongly).
/// Shared between `IconView` and `ListView` for dragging files.
final class FilePromiseProvider: NSFilePromiseProvider {
    private final class Delegate: NSObject, NSFilePromiseProviderDelegate {
        let sourceURL: URL
        let queue = OperationQueue()

        init(sourceURL: URL) {
            self.sourceURL = sourceURL
        }

        func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                                 fileNameForType fileType: String) -> String {
            sourceURL.lastPathComponent
        }

        func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                                 writePromiseTo url: URL,
                                 completionHandler: @escaping (Error?) -> Void) {
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(
                readingItemAt: sourceURL,
                options: [],
                writingItemAt: url,
                options: .forReplacing,
                error: &coordinationError
            ) { readingURL, writingURL in
                do {
                    try FileManager.default.copyItem(at: readingURL, to: writingURL)
                } catch {
                    copyError = error
                }
            }
            completionHandler(copyError ?? coordinationError)
        }

        func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
            queue
        }
    }

    private let promiseDelegate: Delegate

    init(sourceURL: URL) {
        promiseDelegate = Delegate(sourceURL: sourceURL)
        super.init(fileType: UTType.fileURL.identifier, delegate: promiseDelegate)
    }
}
