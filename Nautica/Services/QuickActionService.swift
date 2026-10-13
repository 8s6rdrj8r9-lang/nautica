import AppKit
import Foundation
import PDFKit

/// Central service managing Quick Actions: image rotation, multi-file PDF creation,
/// image format conversions, and direct integration with macOS Shortcuts workflows.
final class QuickActionService {
    static let shared = QuickActionService()

    private(set) var cachedShortcuts: [String] = []

    private init() {
        Task {
            _ = await availableShortcuts()
        }
    }

    // MARK: - Image Operations

    /// Rotates an image file by degrees (e.g. 90 for clockwise, 270 for counter-clockwise) using `sips`.
    @discardableResult
    func rotateImage(at url: URL, degrees: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
                process.arguments = ["-r", "\(degrees)", url.path]
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Converts an image to the specified target format (e.g. "png", "jpeg", "heic", "tiff").
    func convertImage(at url: URL, toFormat format: String) async throws -> URL {
        let destExt = format.lowercased() == "jpeg" ? "jpg" : format.lowercased()
        let parentDir = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        var targetURL = parentDir.appendingPathComponent("\(baseName).\(destExt)")

        var counter = 2
        while FileManager.default.fileExists(atPath: targetURL.path) {
            targetURL = parentDir.appendingPathComponent("\(baseName) \(counter).\(destExt)")
            counter += 1
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
                process.arguments = ["-s", "format", format.lowercased(), url.path, "--out", targetURL.path]
                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: targetURL)
                    } else {
                        continuation.resume(throwing: NSError(domain: "QuickActionService", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to \(format)"]))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - PDF Creation

    /// Combines multiple images or PDFs into a single multi-page PDF document.
    func createPDF(from urls: [URL], in destinationDirectory: URL, baseName: String = "Combined") async throws -> URL {
        guard !urls.isEmpty else {
            throw NSError(domain: "QuickActionService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No items provided for PDF creation"])
        }

        var outputURL = destinationDirectory.appendingPathComponent("\(baseName).pdf")
        var counter = 2
        while FileManager.default.fileExists(atPath: outputURL.path) {
            outputURL = destinationDirectory.appendingPathComponent("\(baseName) \(counter).pdf")
            counter += 1
        }

        let pdfDocument = PDFDocument()
        let imageExtensions = Set(["png", "jpg", "jpeg", "heic", "tiff", "webp", "gif", "bmp"])

        var failedURLs: [URL] = []
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if ext == "pdf" {
                if let existingPDF = PDFDocument(url: url), existingPDF.pageCount > 0 {
                    for pageIndex in 0..<existingPDF.pageCount {
                        if let page = existingPDF.page(at: pageIndex) {
                            pdfDocument.insert(page, at: pdfDocument.pageCount)
                        }
                    }
                } else {
                    failedURLs.append(url)
                }
            } else if imageExtensions.contains(ext) {
                if let image = NSImage(contentsOf: url), let page = PDFPage(image: image) {
                    pdfDocument.insert(page, at: pdfDocument.pageCount)
                } else {
                    failedURLs.append(url)
                }
            } else {
                failedURLs.append(url)
            }
        }

        guard failedURLs.isEmpty else {
            let failedNames = failedURLs.map(\.lastPathComponent).joined(separator: ", ")
            throw NSError(domain: "QuickActionService", code: 422, userInfo: [NSLocalizedDescriptionKey: "Cannot include unreadable or unsupported file(s): \(failedNames)"])
        }

        guard pdfDocument.pageCount > 0 else {
            throw NSError(domain: "QuickActionService", code: 422, userInfo: [NSLocalizedDescriptionKey: "No valid image or PDF pages could be extracted"])
        }

        if !pdfDocument.write(to: outputURL) {
            throw NSError(domain: "QuickActionService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to write PDF file to destination"])
        }

        return outputURL
    }

    // MARK: - macOS Shortcuts CLI Integration

    /// Discovers all available user workflows installed in the macOS Shortcuts application.
    @discardableResult
    func availableShortcuts() async -> [String] {
        let result: [String] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                process.arguments = ["list"]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let text = String(data: data, encoding: .utf8) {
                        let lines = text.components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        continuation.resume(returning: lines)
                        return
                    }
                } catch {
                    // shortcuts CLI unavailable or failed
                }
                continuation.resume(returning: [])
            }
        }
        await MainActor.run {
            self.cachedShortcuts = result
        }
        return result
    }

    /// Synchronous accessor returning cached shortcuts, or querying synchronously if cache is empty.
    func shortcuts() -> [String] {
        if !cachedShortcuts.isEmpty {
            return cachedShortcuts
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        if (try? process.run()) != nil {
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: data, encoding: .utf8) {
                let lines = text.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                self.cachedShortcuts = lines
                return lines
            }
        }
        return []
    }

    /// Executes a named macOS Shortcut with an input file path.
    func runShortcut(name: String, inputFile: URL) async -> (success: Bool, output: String?) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                process.arguments = ["run", name, "-i", inputFile.path]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let outString = String(data: data, encoding: .utf8)
                    continuation.resume(returning: (process.terminationStatus == 0, outString))
                } catch {
                    continuation.resume(returning: (false, error.localizedDescription))
                }
            }
        }
    }
}
