import Foundation
import ImageIO
import PDFKit
import AVFoundation

#if canImport(Darwin)
import Darwin
#endif

/// Service for reading and writing file metadata (EXIF/Image, PDF, Audio/ID3) atomically and losslessly,
/// while synchronizing changes with macOS Spotlight extended attributes.
public final class MetadataEditorService: @unchecked Sendable {
    public static let shared = MetadataEditorService()

    public enum MetadataEditorError: LocalizedError {
        case fileNotFound
        case cannotReadSource
        case unsupportedFormat
        case cannotCreateDestination
        case cannotFinalize
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "The target file could not be found."
            case .cannotReadSource:
                return "Unable to read metadata from the selected file."
            case .unsupportedFormat:
                return "The file format does not support metadata editing."
            case .cannotCreateDestination:
                return "Could not create destination stream for writing metadata."
            case .cannotFinalize:
                return "Failed to finalize and save updated metadata."
            case .writeFailed(let message):
                return "Failed to write metadata: \(message)"
            }
        }
    }

    private init() {}

    // MARK: - Image Metadata Writing (Lossless via ImageIO)

    /// Updates image metadata (TIFF, IPTC, and EXIF dictionaries) in-place without re-compressing pixel data.
    public func writeImageMetadata(
        at url: URL,
        title: String? = nil,
        author: String? = nil,
        copyright: String? = nil,
        keywords: [String]? = nil,
        comment: String? = nil
    ) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MetadataEditorError.fileNotFound
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw MetadataEditorError.cannotReadSource
        }
        guard let uti = CGImageSourceGetType(source) else {
            throw MetadataEditorError.unsupportedFormat
        }

        let count = CGImageSourceGetCount(source)
        guard count > 0 else {
            throw MetadataEditorError.cannotReadSource
        }

        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".tmp_\(UUID().uuidString)_\(url.lastPathComponent)")

        guard let destination = CGImageDestinationCreateWithURL(tempURL as CFURL, uti, count, nil) else {
            throw MetadataEditorError.cannotCreateDestination
        }

        for i in 0..<count {
            var props = (CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]) ?? [:]

            // 1. TIFF Dictionary: Title (ImageDescription), Artist/Author, Copyright
            var tiff = (props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]) ?? [:]
            if let title { tiff[kCGImagePropertyTIFFImageDescription] = title as CFString }
            if let author { tiff[kCGImagePropertyTIFFArtist] = author as CFString }
            if let copyright { tiff[kCGImagePropertyTIFFCopyright] = copyright as CFString }
            props[kCGImagePropertyTIFFDictionary] = tiff

            // 2. IPTC Dictionary: Caption/Abstract, Byline/Author, Copyright, Keywords
            var iptc = (props[kCGImagePropertyIPTCDictionary] as? [CFString: Any]) ?? [:]
            if let title { iptc[kCGImagePropertyIPTCCaptionAbstract] = title as CFString }
            if let author { iptc[kCGImagePropertyIPTCByline] = author as CFString }
            if let copyright { iptc[kCGImagePropertyIPTCCopyrightNotice] = copyright as CFString }
            if let keywords { iptc[kCGImagePropertyIPTCKeywords] = keywords as CFArray }
            props[kCGImagePropertyIPTCDictionary] = iptc

            // 3. EXIF Dictionary: UserComment
            if let comment {
                var exif = (props[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
                exif[kCGImagePropertyExifUserComment] = comment as CFString
                props[kCGImagePropertyExifDictionary] = exif
            }

            CGImageDestinationAddImageFromSource(destination, source, i, props as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: tempURL)
            throw MetadataEditorError.cannotFinalize
        }

        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)

        // Sync Spotlight attributes
        syncSpotlightAttributes(
            for: url,
            title: title,
            authors: author.map { [$0] },
            comment: comment,
            keywords: keywords
        )
    }

    // MARK: - PDF Metadata Writing (via PDFKit)

    /// Updates PDF document attributes (Title, Author, Subject, Keywords) atomically.
    public func writePDFMetadata(
        at url: URL,
        title: String? = nil,
        author: String? = nil,
        subject: String? = nil,
        keywords: [String]? = nil
    ) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MetadataEditorError.fileNotFound
        }

        guard let document = PDFDocument(url: url) else {
            throw MetadataEditorError.cannotReadSource
        }

        var attributes = document.documentAttributes ?? [:]
        if let title { attributes[PDFDocumentAttribute.titleAttribute] = title }
        if let author { attributes[PDFDocumentAttribute.authorAttribute] = author }
        if let subject { attributes[PDFDocumentAttribute.subjectAttribute] = subject }
        if let keywords { attributes[PDFDocumentAttribute.keywordsAttribute] = keywords }

        document.documentAttributes = attributes

        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".tmp_\(UUID().uuidString)_\(url.lastPathComponent)")

        guard document.write(to: tempURL) else {
            throw MetadataEditorError.cannotFinalize
        }

        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)

        // Sync Spotlight attributes
        syncSpotlightAttributes(
            for: url,
            title: title,
            authors: author.map { [$0] },
            comment: subject,
            keywords: keywords
        )
    }

    // MARK: - Audio Metadata Writing (ID3v2 for MP3, AVMutableMovie for M4A, Spotlight Sync)

    /// Updates audio metadata (Title, Artist, Album, Year) across MP3, M4A, and standard audio formats.
    public func writeAudioMetadata(
        at url: URL,
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        year: String? = nil
    ) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MetadataEditorError.fileNotFound
        }

        let ext = url.pathExtension.lowercased()
        if ext == "mp3" {
            try writeMP3ID3Metadata(at: url, title: title, artist: artist, album: album, year: year)
        } else if ext == "m4a" || ext == "mp4" || ext == "mov" {
            try writeM4AMetadata(at: url, title: title, artist: artist, album: album)
        }

        // Always sync Spotlight extended attributes for rapid search & indexing
        syncSpotlightAttributes(
            for: url,
            title: title,
            authors: artist.map { [$0] },
            comment: album.map { "Album: \($0)" },
            keywords: album.map { [$0] }
        )
    }

    // MARK: - MP3 ID3v2 Writer

    private func writeMP3ID3Metadata(
        at url: URL,
        title: String?,
        artist: String?,
        album: String?,
        year: String?
    ) throws {
        let fileData = try Data(contentsOf: url)
        var audioOffset = 0

        // Check if existing ID3v2 tag is present at the beginning
        if fileData.count >= 10 &&
            fileData[0] == 0x49 && fileData[1] == 0x44 && fileData[2] == 0x33 {
            // ID3v2 tag found; calculate tag size from syncsafe integer at bytes 6..9
            let s0 = Int(fileData[6] & 0x7F)
            let s1 = Int(fileData[7] & 0x7F)
            let s2 = Int(fileData[8] & 0x7F)
            let s3 = Int(fileData[9] & 0x7F)
            let tagSize = (s0 << 21) | (s1 << 14) | (s2 << 7) | s3
            audioOffset = 10 + tagSize
            if audioOffset > fileData.count {
                audioOffset = 0
            }
        }

        let rawAudioData = (audioOffset > 0 && audioOffset < fileData.count)
            ? fileData.subdata(in: audioOffset..<fileData.count)
            : fileData

        // Parse existing frames from existing ID3 tag to preserve untouched metadata
        var existingFrames: [(id: String, frameBytes: Data)] = []
        if audioOffset > 10 {
            var cursor = 10
            while cursor + 10 <= audioOffset {
                let idBytes = fileData.subdata(in: cursor..<cursor + 4)
                guard idBytes[0] != 0, let frameID = String(data: idBytes, encoding: .ascii) else {
                    // Padding or end of frames
                    break
                }
                // Big-endian 4-byte size
                let sizeBytes = fileData.subdata(in: cursor + 4..<cursor + 8)
                let framePayloadSize = Int(sizeBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                let fullFrameSize = 10 + framePayloadSize
                guard fullFrameSize > 10, cursor + fullFrameSize <= audioOffset else {
                    break
                }
                let fullFrameData = fileData.subdata(in: cursor..<cursor + fullFrameSize)
                existingFrames.append((id: frameID, frameBytes: fullFrameData))
                cursor += fullFrameSize
            }
        }

        // Build new ID3v2.3 tag payload
        var frameData = Data()

        // Frame IDs being updated by this call
        var updatedFrameIDs = Set<String>()
        if title != nil { updatedFrameIDs.insert("TIT2") }
        if artist != nil { updatedFrameIDs.insert("TPE1") }
        if album != nil { updatedFrameIDs.insert("TALB") }
        if year != nil { updatedFrameIDs.insert("TYER") }

        // Retain all existing frames that are NOT being updated!
        for existing in existingFrames where !updatedFrameIDs.contains(existing.id) {
            frameData.append(existing.frameBytes)
        }

        func appendTextFrame(id: String, text: String?) {
            guard let text = text, !text.isEmpty else { return }
            guard let textBytes = text.data(using: .utf8) else { return }

            var frame = Data()
            // 4-byte Frame ID
            frame.append(contentsOf: id.utf8)
            // 4-byte size (textBytes + 1 byte for encoding flag 0x03)
            let frameSize = UInt32(textBytes.count + 1)
            var bigEndianSize = frameSize.bigEndian
            withUnsafeBytes(of: &bigEndianSize) { frame.append(contentsOf: $0) }
            // 2-byte flags (0x00, 0x00)
            frame.append(contentsOf: [0x00, 0x00])
            // 1-byte encoding: 0x03 is UTF-8
            frame.append(0x03)
            // Text payload
            frame.append(textBytes)

            frameData.append(frame)
        }

        appendTextFrame(id: "TIT2", text: title)
        appendTextFrame(id: "TPE1", text: artist)
        appendTextFrame(id: "TALB", text: album)
        appendTextFrame(id: "TYER", text: year)

        // Build 10-byte header
        var header = Data()
        header.append(contentsOf: [0x49, 0x44, 0x33]) // "ID3"
        header.append(contentsOf: [0x03, 0x00])       // Version 2.3
        header.append(0x00)                         // Flags: none

        // Syncsafe integer for total frameData.count
        let totalSize = frameData.count
        let b0 = UInt8((totalSize >> 21) & 0x7F)
        let b1 = UInt8((totalSize >> 14) & 0x7F)
        let b2 = UInt8((totalSize >> 7) & 0x7F)
        let b3 = UInt8(totalSize & 0x7F)
        header.append(contentsOf: [b0, b1, b2, b3])

        var newFileContent = Data()
        newFileContent.append(header)
        newFileContent.append(frameData)
        newFileContent.append(rawAudioData)

        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".tmp_\(UUID().uuidString)_\(url.lastPathComponent)")

        try newFileContent.write(to: tempURL, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }

    private func writeM4AMetadata(
        at url: URL,
        title: String?,
        artist: String?,
        album: String?
    ) throws {
        let movie = AVMutableMovie(url: url, options: nil)
        var items = movie.metadata
        func updateItem(key: AVMetadataKey, value: String?) {
            guard let value = value else { return }
            items.removeAll { ($0.key as? AVMetadataKey) == key }
            let item = AVMutableMetadataItem()
            item.keySpace = .common
            item.key = key as (NSCopying & NSObjectProtocol)
            item.value = value as (NSCopying & NSObjectProtocol)
            items.append(item)
        }

        updateItem(key: .commonKeyTitle, value: title)
        updateItem(key: .commonKeyArtist, value: artist)
        updateItem(key: .commonKeyAlbumName, value: album)

        movie.metadata = items
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".tmp_\(UUID().uuidString)_\(url.lastPathComponent)")

        try movie.writeHeader(to: tempURL, fileType: .m4a)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }

    // MARK: - Spotlight Extended Attributes Synchronization

    /// Synchronizes standard metadata fields with macOS Extended Attributes so Spotlight & Finder
    /// can immediately index and search the modified file attributes.
    public func syncSpotlightAttributes(
        for url: URL,
        title: String? = nil,
        authors: [String]? = nil,
        comment: String? = nil,
        keywords: [String]? = nil
    ) {
        let path = url.path(percentEncoded: false)

        if let title, !title.isEmpty {
            setExtendedAttribute(name: "com.apple.metadata:kMDItemTitle", stringValue: title, for: path)
        }

        if let authors, !authors.isEmpty {
            setExtendedAttribute(name: "com.apple.metadata:kMDItemAuthors", plistValue: authors, for: path)
        }

        if let comment, !comment.isEmpty {
            setExtendedAttribute(name: "com.apple.metadata:kMDItemFinderComment", stringValue: comment, for: path)
            setExtendedAttribute(name: "com.apple.metadata:kMDItemDescription", stringValue: comment, for: path)
        }

        if let keywords, !keywords.isEmpty {
            setExtendedAttribute(name: "com.apple.metadata:kMDItemKeywords", plistValue: keywords, for: path)
        }
    }

    // MARK: - Extended Attributes Helpers

    private func setExtendedAttribute(name: String, stringValue: String, for path: String) {
        guard let data = stringValue.data(using: .utf8) else { return }
        data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress else { return }
            _ = setxattr(path, name, ptr, data.count, 0, 0)
        }
    }

    private func setExtendedAttribute(name: String, plistValue: Any, for path: String) {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plistValue, format: .binary, options: 0) else {
            return
        }
        data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress else { return }
            _ = setxattr(path, name, ptr, data.count, 0, 0)
        }
    }

    public func getExtendedAttributeString(name: String, for path: String) -> String? {
        let size = getxattr(path, name, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let readSize = data.withUnsafeMutableBytes { ptr in
            getxattr(path, name, ptr.baseAddress, size, 0, 0)
        }
        guard readSize > 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
