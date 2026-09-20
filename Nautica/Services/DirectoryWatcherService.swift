import Foundation

/// Watches a directory on the local filesystem for real-time changes
/// (creations, deletions, renames, writes) using DispatchSource.
/// Events are debounced (150ms) to prevent UI thrashing during rapid batch writes.
final class DirectoryWatcherService: @unchecked Sendable {
    private let url: URL
    private let onChange: @MainActor () -> Void
    private var fileDescriptor: Int32 = -1
    private var source: (any DispatchSourceFileSystemObject)?
    private let queue = DispatchQueue(label: "com.arthur.nautica.directory-watcher", qos: .utility)
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.15

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.onChange = onChange
        startWatching()
    }

    deinit {
        stopWatching()
    }

    func startWatching() {
        stopWatching()

        guard url.isFileURL else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .attrib, .extend],
            queue: queue
        )

        src.setEventHandler { [weak self] in
            self?.scheduleChangeNotification()
        }

        src.setCancelHandler { [fd] in
            close(fd)
        }

        source = src
        src.resume()
    }

    func stopWatching() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        if let source {
            source.cancel()
            self.source = nil
            fileDescriptor = -1
        } else if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    private func scheduleChangeNotification() {
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.onChange()
            }
        }

        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}
