import SwiftUI
import AppKit
import CryptoKit

/// Right sidebar panel offering one-click batch utilities, path formatting, checksums, and compression.
struct QuickActionsPanelView: View {
    let selectedItems: [FileItem]
    let currentFolderURL: URL
    var onReloadDirectory: () -> Void
    var onOpenTerminal: (URL) -> Void

    @State private var sha256Hash: String?
    @State private var md5Hash: String?
    @State private var isCalculatingHash = false
    @State private var statusMessage: String?
    @State private var statusTimer: Task<Void, Never>?

    private var activeURL: URL {
        selectedItems.first?.url ?? currentFolderURL
    }

    private var isImageFile: Bool {
        guard let item = selectedItems.first, selectedItems.count == 1 else { return false }
        let ext = item.url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "webp", "tiff", "gif", "heic"].contains(ext)
    }

    private var hasImages: Bool {
        let exts: Set<String> = ["png", "jpg", "jpeg", "webp", "tiff", "gif", "heic"]
        return selectedItems.contains { exts.contains($0.url.pathExtension.lowercased()) }
    }

    private var hasPDFs: Bool {
        selectedItems.contains { $0.url.pathExtension.lowercased() == "pdf" }
    }

    private var isZipFile: Bool {
        guard let item = selectedItems.first, selectedItems.count == 1 else { return false }
        return item.url.pathExtension.lowercased() == "zip"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack {
                    Label("Quick Actions", systemImage: "wand.and.stars")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                }

                if let statusMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text(statusMessage)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // Section 1: Archive & Extraction
                actionSection("Archive & Compression") {
                    if isZipFile, let item = selectedItems.first {
                        Button(action: { unarchiveZip(item.url) }) {
                            Label("Extract Archive", systemImage: "arrow.up.bin")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .controlSize(.small)
                    }

                    Button(action: createArchive) {
                        let label = selectedItems.isEmpty ? "Compress Folder (\(currentFolderURL.lastPathComponent).zip)" : "Compress Selection (\(selectedItems.count) items)"
                        Label(label, systemImage: "archivebox")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .controlSize(.small)
                }

                Divider()

                // Section 2: Copy Path Variants
                actionSection("Copy Path Variants") {
                    copyPathRow(label: "POSIX Path", value: activeURL.path)
                    copyPathRow(label: "Quoted / Shell", value: "\"\(activeURL.path.replacingOccurrences(of: "\"", with: "\\\""))\"")
                    copyPathRow(label: "File URL", value: activeURL.absoluteString)
                    copyPathRow(label: "Name Only", value: activeURL.lastPathComponent)
                }

                Divider()

                // Section 3: Checksums (Hashes)
                if selectedItems.count == 1, let item = selectedItems.first, !item.isDirectory {
                    actionSection("Checksums") {
                        if isCalculatingHash {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Calculating hash…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if let sha256 = sha256Hash {
                            hashRow(name: "SHA-256", hash: sha256)
                            if let md5 = md5Hash {
                                hashRow(name: "MD5", hash: md5)
                            }
                        } else {
                            Button(action: calculateHashes) {
                                Label("Calculate SHA-256 & MD5", systemImage: "number")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .controlSize(.small)
                        }
                    }

                    Divider()
                }

                // Section 4: Document & Image Actions (Rotate & PDF)
                if hasImages || hasPDFs {
                    actionSection("Document & Image Actions") {
                        if hasImages {
                            HStack(spacing: 6) {
                                Button(action: rotateSelectedImagesLeft) {
                                    Label("Rotate Left", systemImage: "rotate.left")
                                        .frame(maxWidth: .infinity)
                                }
                                .controlSize(.small)

                                Button(action: rotateSelectedImagesRight) {
                                    Label("Rotate Right", systemImage: "rotate.right")
                                        .frame(maxWidth: .infinity)
                                }
                                .controlSize(.small)
                            }
                        }

                        Button(action: createPDFFromSelection) {
                            Label("Create PDF", systemImage: "doc.richtext")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .controlSize(.small)
                    }

                    Divider()
                }

                // Section 5: Image Conversion
                if isImageFile, let item = selectedItems.first {
                    actionSection("Image Conversion") {
                        HStack(spacing: 6) {
                            convertImageButton("PNG", format: .png, source: item.url)
                            convertImageButton("JPEG", format: .jpeg, source: item.url)
                            convertImageButton("TIFF", format: .tiff, source: item.url)
                        }
                    }

                    Divider()
                }

                // Section 6: Shortcuts
                let shortcuts = QuickActionService.shared.shortcuts()
                if !shortcuts.isEmpty && !selectedItems.isEmpty {
                    actionSection("Shortcuts") {
                        ForEach(shortcuts.prefix(5), id: \.self) { shortcut in
                            Button(action: { runShortcut(shortcut) }) {
                                Label(shortcut, systemImage: "bolt.fill")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .controlSize(.small)
                        }
                    }

                    Divider()
                }

                // Section 5: Utilities
                actionSection("Utilities") {
                    Button(action: createNewTextFile) {
                        Label("New Plain Text File", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .controlSize(.small)

                    Button(action: { onOpenTerminal(currentFolderURL) }) {
                        Label("Open in Terminal", systemImage: "terminal")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .controlSize(.small)
                }
            }
            .padding(12)
        }
        .onChange(of: selectedItems) {
            sha256Hash = nil
            md5Hash = nil
            isCalculatingHash = false
        }
    }

    // MARK: - Actions

    private func createArchive() {
        let items = selectedItems.isEmpty ? [currentFolderURL] : selectedItems.map(\.url)
        let destinationDir = currentFolderURL
        let archiveName: String
        if selectedItems.count == 1, let first = selectedItems.first {
            archiveName = "\(first.url.deletingPathExtension().lastPathComponent).zip"
        } else if selectedItems.count > 1 {
            archiveName = "Archive.zip"
        } else {
            archiveName = "\(currentFolderURL.lastPathComponent).zip"
        }

        let zipURL = destinationDir.appendingPathComponent(archiveName)

        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            var args = ["-c", "-k", "--sequesterRsrc"]
            args.append(contentsOf: items.map(\.path))
            args.append(zipURL.path)
            process.arguments = args
            try? process.run()
            process.waitUntilExit()

            await MainActor.run {
                flashStatus("Created \(archiveName)")
                onReloadDirectory()
            }
        }
    }

    private func unarchiveZip(_ zipURL: URL) {
        let dest = zipURL.deletingPathExtension()
        Task.detached(priority: .userInitiated) {
            try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-q", zipURL.path, "-d", dest.path]
            try? process.run()
            process.waitUntilExit()

            await MainActor.run {
                flashStatus("Extracted to \(dest.lastPathComponent)")
                onReloadDirectory()
            }
        }
    }

    private func calculateHashes() {
        guard let item = selectedItems.first else { return }
        isCalculatingHash = true
        let url = item.url
        Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                await MainActor.run { isCalculatingHash = false }
                return
            }
            let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let md5 = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()

            await MainActor.run {
                sha256Hash = sha
                md5Hash = md5
                isCalculatingHash = false
            }
        }
    }

    private func convertImageButton(_ title: String, format: NSBitmapImageRep.FileType, source: URL) -> some View {
        Button(title) {
            convertImage(source, to: format)
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity)
    }

    private func convertImage(_ url: URL, to type: NSBitmapImageRep.FileType) {
        guard let image = NSImage(contentsOf: url),
              let tiffData = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData) else { return }

        let ext: String
        switch type {
        case .png: ext = "png"
        case .jpeg: ext = "jpg"
        case .tiff: ext = "tiff"
        default: ext = "img"
        }

        let outputURL = url.deletingPathExtension().appendingPathExtension(ext)
        if let data = rep.representation(using: type, properties: [:]) {
            try? data.write(to: outputURL)
            flashStatus("Converted to .\(ext)")
            onReloadDirectory()
        }
    }

    private func rotateSelectedImagesLeft() {
        let urls = selectedItems.map(\.url)
        Task {
            for url in urls {
                await QuickActionService.shared.rotateImage(at: url, degrees: 270)
            }
            await MainActor.run {
                flashStatus("Rotated image(s) 90° CCW")
                onReloadDirectory()
            }
        }
    }

    private func rotateSelectedImagesRight() {
        let urls = selectedItems.map(\.url)
        Task {
            for url in urls {
                await QuickActionService.shared.rotateImage(at: url, degrees: 90)
            }
            await MainActor.run {
                flashStatus("Rotated image(s) 90° CW")
                onReloadDirectory()
            }
        }
    }

    private func createPDFFromSelection() {
        let urls = selectedItems.map(\.url)
        Task {
            if let _ = try? await QuickActionService.shared.createPDF(from: urls, in: currentFolderURL) {
                await MainActor.run {
                    flashStatus("Created PDF document")
                    onReloadDirectory()
                }
            }
        }
    }

    private func runShortcut(_ name: String) {
        guard let first = selectedItems.first else { return }
        Task {
            if let result = try? await QuickActionService.shared.runShortcut(name: name, inputFile: first.url) {
                await MainActor.run {
                    let preview = result.output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    flashStatus("Shortcut done: \(preview.isEmpty ? name : String(preview.prefix(20)))")
                    onReloadDirectory()
                }
            }
        }
    }

    private func createNewTextFile() {
        var counter = 1
        var candidate = currentFolderURL.appendingPathComponent("untitled.txt")
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = currentFolderURL.appendingPathComponent("untitled \(counter).txt")
            counter += 1
        }
        try? "".write(to: candidate, atomically: true, encoding: .utf8)
        flashStatus("Created \(candidate.lastPathComponent)")
        onReloadDirectory()
    }

    private func flashStatus(_ msg: String) {
        statusTimer?.cancel()
        statusMessage = msg
        statusTimer = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            statusMessage = nil
        }
    }

    // MARK: - View Helpers

    private func actionSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func copyPathRow(label: String, value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                flashStatus("Copied \(label)")
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Copy \(label)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func hashRow(name: String, hash: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(hash, forType: .string)
                    flashStatus("Copied \(name)")
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
            }
            Text(hash)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(6)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
