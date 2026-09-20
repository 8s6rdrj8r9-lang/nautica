import SwiftUI
import AppKit
import ImageIO
import AVFoundation
import PDFKit

/// Media metadata extracted from images, audio, video, or PDF documents.
struct MediaDetails {
    var mediaType: MediaType = .other
    var dimensions: String?
    var megapixels: String?
    var colorSpace: String?
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var focalLength: String?
    var aperture: String?
    var shutterSpeed: String?
    var iso: String?
    var flashFired: Bool?
    var duration: String?
    var frameRate: String?
    var videoCodec: String?
    var audioCodec: String?
    var audioChannels: String?
    var sampleRate: String?
    var bitrate: String?
    var title: String?
    var artist: String?
    var album: String?
    var year: String?
    var copyright: String?
    var comment: String?
    var keywords: [String] = []
    var subject: String?
    var pageCount: Int?

    enum MediaType {
        case image
        case audio
        case video
        case pdf
        case other
    }
}

/// Right sidebar panel displaying deep EXIF, camera, audio, video, and PDF document metadata,
/// featuring an interactive in-place metadata editor with atomic disk saving and Spotlight synchronization.
struct MediaMetadataPanelView: View {
    let selectedItem: FileItem?
    var onQuickLook: () -> Void
    var onReloadDirectory: (() -> Void)? = nil

    @State private var details: MediaDetails?
    @State private var isLoading = false
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var showSavedToast = false
    @State private var errorMessage: String? = nil

    // Editing State Fields
    @State private var editTitle: String = ""
    @State private var editAuthor: String = ""
    @State private var editSubject: String = ""
    @State private var editAlbum: String = ""
    @State private var editYear: String = ""
    @State private var editKeywords: String = ""
    @State private var editComment: String = ""

    private var isEditable: Bool {
        guard let details = details else { return false }
        return details.mediaType == .image || details.mediaType == .pdf || details.mediaType == .audio
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Media & Metadata", systemImage: "pencil.and.list.clipboard")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                if let _ = selectedItem, isEditable && !isLoading {
                    Button {
                        if isEditing {
                            cancelEditing()
                        } else {
                            startEditing()
                        }
                    } label: {
                        Text(isEditing ? "Done" : "Edit")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isEditing ? Color.secondary : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if let selectedItem {
                if selectedItem.cloudStatus == .onlineOnly {
                    onlineOnlyCloudView(selectedItem)
                } else if isLoading {
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Text("Reading file properties…").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let details, details.mediaType != .other {
                    if isEditing {
                        editorFormView(item: selectedItem, details: details)
                    } else {
                        mediaContentView(item: selectedItem, details: details)
                    }
                } else {
                    nonMediaSelectedView(selectedItem)
                }
            } else {
                emptySelectionView
            }
        }
        .task(id: selectedItem?.url) {
            isEditing = false
            loadMediaDetails()
        }
    }

    // MARK: - Read-Only View

    private func mediaContentView(item: FileItem, details: MediaDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header Thumbnail & Title
                VStack(spacing: 6) {
                    if let icon = item.iconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .shadow(color: .black.opacity(0.1), radius: 2)
                    }

                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    if let dim = details.dimensions {
                        Text(dim + (details.megapixels.map { " (\($0))" } ?? ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let pages = details.pageCount {
                        Text("\(pages) page\(pages == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)

                // Quick Look Action & Saved Toast
                VStack(spacing: 6) {
                    Button(action: onQuickLook) {
                        Label("Preview File", systemImage: "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.small)

                    if showSavedToast {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Metadata updated successfully")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .transition(.opacity)
                    }
                }

                Divider()

                // Common Document / Media Annotations
                if details.title != nil || details.artist != nil || details.subject != nil || !details.keywords.isEmpty || details.comment != nil {
                    metadataSection("Description & Annotations") {
                        if let title = details.title { metaRow("Title", title) }
                        if let artist = details.artist {
                            metaRow(details.mediaType == .pdf ? "Author" : (details.mediaType == .audio ? "Artist" : "Photographer"), artist)
                        }
                        if let album = details.album { metaRow("Album", album) }
                        if let subject = details.subject { metaRow("Subject", subject) }
                        if let comment = details.comment { metaRow("Notes", comment) }
                        if !details.keywords.isEmpty {
                            metaRow("Keywords", details.keywords.joined(separator: ", "))
                        }
                    }
                    Divider()
                }

                // PDF Specifics
                if details.mediaType == .pdf {
                    metadataSection("PDF Document") {
                        if let pages = details.pageCount { metaRow("Pages", "\(pages)") }
                    }
                }

                // Image Properties / Camera EXIF
                if details.mediaType == .image {
                    if details.cameraMake != nil || details.cameraModel != nil || details.lensModel != nil {
                        metadataSection("Camera & Optics") {
                            if let make = details.cameraMake { metaRow("Make", make) }
                            if let model = details.cameraModel { metaRow("Model", model) }
                            if let lens = details.lensModel { metaRow("Lens", lens) }
                            if let focal = details.focalLength { metaRow("Focal Length", focal) }
                        }
                        Divider()
                    }

                    if details.aperture != nil || details.shutterSpeed != nil || details.iso != nil {
                        metadataSection("Exposure") {
                            if let ap = details.aperture { metaRow("Aperture", ap) }
                            if let ss = details.shutterSpeed { metaRow("Shutter Speed", ss) }
                            if let iso = details.iso { metaRow("ISO", iso) }
                            if let flash = details.flashFired { metaRow("Flash", flash ? "Fired" : "Did not fire") }
                        }
                        Divider()
                    }

                    metadataSection("Image Specifications") {
                        if let dim = details.dimensions { metaRow("Dimensions", dim) }
                        if let mp = details.megapixels { metaRow("Resolution", mp) }
                        if let cs = details.colorSpace { metaRow("Color Space", cs) }
                    }
                }

                // Video Properties
                if details.mediaType == .video {
                    metadataSection("Video Stream") {
                        if let dim = details.dimensions { metaRow("Resolution", dim) }
                        if let dur = details.duration { metaRow("Duration", dur) }
                        if let fps = details.frameRate { metaRow("Frame Rate", fps) }
                        if let vcodec = details.videoCodec { metaRow("Video Codec", vcodec) }
                    }
                    Divider()

                    if details.audioCodec != nil || details.audioChannels != nil {
                        metadataSection("Audio Stream") {
                            if let acodec = details.audioCodec { metaRow("Audio Codec", acodec) }
                            if let ch = details.audioChannels { metaRow("Channels", ch) }
                            if let sr = details.sampleRate { metaRow("Sample Rate", sr) }
                        }
                    }
                }

                // Audio Properties
                if details.mediaType == .audio {
                    metadataSection("Audio Specifications") {
                        if let dur = details.duration { metaRow("Duration", dur) }
                        if let br = details.bitrate { metaRow("Bitrate", br) }
                        if let sr = details.sampleRate { metaRow("Sample Rate", sr) }
                        if let ch = details.audioChannels { metaRow("Channels", ch) }
                        if let ac = details.audioCodec { metaRow("Format", ac) }
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - In-Place Editor Form

    private func editorFormView(item: FileItem, details: MediaDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Edit Metadata")
                        .font(.system(size: 13, weight: .semibold))

                    Spacer()

                    if isSaving {
                        ProgressView().controlSize(.small)
                    }
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 10) {
                    // Title field
                    formField("Title", text: $editTitle, placeholder: "Title or Caption")

                    // Author / Artist field
                    let authorLabel = (details.mediaType == .pdf) ? "Author" : (details.mediaType == .audio ? "Artist" : "Photographer")
                    formField(authorLabel, text: $editAuthor, placeholder: "Author or Creator name")

                    // Audio specific fields
                    if details.mediaType == .audio {
                        formField("Album", text: $editAlbum, placeholder: "Album name")
                        formField("Year", text: $editYear, placeholder: "e.g. 2026")
                    }

                    // PDF specific fields
                    if details.mediaType == .pdf {
                        formField("Subject", text: $editSubject, placeholder: "Document Subject")
                    }

                    // Keywords (Images & PDFs)
                    if details.mediaType == .image || details.mediaType == .pdf {
                        formField("Keywords", text: $editKeywords, placeholder: "Comma separated (e.g. landscape, summer)")
                    }

                    // User Notes / Comment (Images)
                    if details.mediaType == .image {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes / Comment")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextEditor(text: $editComment)
                                .font(.system(size: 11))
                                .frame(height: 55)
                                .border(Color.secondary.opacity(0.2), width: 1)
                        }
                    }
                }

                Divider()

                // Save & Cancel Buttons
                HStack(spacing: 8) {
                    Button("Cancel") {
                        cancelEditing()
                    }
                    .controlSize(.small)
                    .disabled(isSaving)

                    Spacer()

                    Button {
                        saveMetadata()
                    } label: {
                        HStack(spacing: 4) {
                            if isSaving {
                                ProgressView().controlSize(.small)
                            }
                            Text("Save Changes")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isSaving)
                }
            }
            .padding(12)
        }
    }

    private func formField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
        }
    }

    private func startEditing() {
        guard let details = details else { return }
        editTitle = details.title ?? ""
        editAuthor = details.artist ?? ""
        editSubject = details.subject ?? ""
        editAlbum = details.album ?? ""
        editYear = details.year ?? ""
        editKeywords = details.keywords.joined(separator: ", ")
        editComment = details.comment ?? ""
        errorMessage = nil
        isEditing = true
    }

    private func cancelEditing() {
        isEditing = false
        errorMessage = nil
    }

    private func saveMetadata() {
        guard let item = selectedItem else { return }
        isSaving = true
        errorMessage = nil

        let title = editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = editAuthor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : editAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = editSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : editSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        let album = editAlbum.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : editAlbum.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = editYear.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : editYear.trimmingCharacters(in: .whitespacesAndNewlines)
        let comment = editComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : editComment.trimmingCharacters(in: .whitespacesAndNewlines)
        let kwList = editKeywords.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let keywords = kwList.isEmpty ? nil : kwList

        Task {
            do {
                if details?.mediaType == .image {
                    try MetadataEditorService.shared.writeImageMetadata(
                        at: item.url,
                        title: title,
                        author: author,
                        keywords: keywords,
                        comment: comment
                    )
                } else if details?.mediaType == .pdf {
                    try MetadataEditorService.shared.writePDFMetadata(
                        at: item.url,
                        title: title,
                        author: author,
                        subject: subject,
                        keywords: keywords
                    )
                } else if details?.mediaType == .audio {
                    try MetadataEditorService.shared.writeAudioMetadata(
                        at: item.url,
                        title: title,
                        artist: author,
                        album: album,
                        year: year
                    )
                }

                await MainActor.run {
                    isSaving = false
                    isEditing = false
                    showSavedToast = true
                    loadMediaDetails()
                    onReloadDirectory?()

                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await MainActor.run {
                            showSavedToast = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - State Placeholders

    private var emptySelectionView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text("No File Selected")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Select an image, PDF document, song, or video to view and edit metadata.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func nonMediaSelectedView(_ item: FileItem) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: item.isDirectory ? "folder" : "doc")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text(item.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text("This file format does not support media or document metadata streams.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func onlineOnlyCloudView(_ item: FileItem) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 38))
                .foregroundStyle(Color.accentColor)

            Text(item.name)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 16)

            Text("Stored in Cloud")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text("This file hasn't been downloaded locally yet. Download it to inspect and edit metadata.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button {
                try? FileManager.default.startDownloadingUbiquitousItem(at: item.url)
            } label: {
                Label("Download Now", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func metadataSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 85, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    // MARK: - Metadata Extraction

    private func loadMediaDetails() {
        guard let item = selectedItem, !item.isDirectory else {
            details = nil
            return
        }

        guard item.cloudStatus != .onlineOnly else {
            details = nil
            isLoading = false
            return
        }

        let url = item.url
        let ext = url.pathExtension.lowercased()
        let imageExtensions = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "raw", "dng", "cr2", "nef", "webp", "gif"]
        let audioExtensions = ["mp3", "m4a", "wav", "flac", "aac", "aiff", "alac"]
        let videoExtensions = ["mp4", "mov", "m4v", "mkv", "avi", "webm"]
        let pdfExtensions = ["pdf"]

        isLoading = true

        Task.detached(priority: .userInitiated) {
            var result = MediaDetails()

            if imageExtensions.contains(ext) {
                result.mediaType = .image
                Self.extractImageMetadata(from: url, into: &result)
            } else if pdfExtensions.contains(ext) {
                result.mediaType = .pdf
                Self.extractPDFMetadata(from: url, into: &result)
            } else if audioExtensions.contains(ext) {
                result.mediaType = .audio
                await Self.extractAudioMetadata(from: url, into: &result)
            } else if videoExtensions.contains(ext) {
                result.mediaType = .video
                await Self.extractVideoMetadata(from: url, into: &result)
            } else {
                result.mediaType = .other
            }

            await MainActor.run {
                self.details = result
                self.isLoading = false
            }
        }
    }

    private static func extractPDFMetadata(from url: URL, into result: inout MediaDetails) {
        guard let doc = PDFDocument(url: url) else { return }
        result.pageCount = doc.pageCount
        if let attrs = doc.documentAttributes {
            result.title = attrs[PDFDocumentAttribute.titleAttribute] as? String
            result.artist = attrs[PDFDocumentAttribute.authorAttribute] as? String
            result.subject = attrs[PDFDocumentAttribute.subjectAttribute] as? String
            if let kw = attrs[PDFDocumentAttribute.keywordsAttribute] as? [String] {
                result.keywords = kw
            } else if let kwStr = attrs[PDFDocumentAttribute.keywordsAttribute] as? String {
                result.keywords = kwStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }
        }
    }

    private static func extractImageMetadata(from url: URL, into result: inout MediaDetails) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return }

        if let width = props[kCGImagePropertyPixelWidth] as? Int,
           let height = props[kCGImagePropertyPixelHeight] as? Int {
            result.dimensions = "\(width) × \(height) px"
            let mp = Double(width * height) / 1_000_000.0
            result.megapixels = String(format: "%.1f MP", mp)
        }

        if let colorModel = props[kCGImagePropertyColorModel] as? String {
            result.colorSpace = colorModel
        }

        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            result.cameraMake = tiff[kCGImagePropertyTIFFMake] as? String
            result.cameraModel = tiff[kCGImagePropertyTIFFModel] as? String
            if let desc = tiff[kCGImagePropertyTIFFImageDescription] as? String {
                result.title = desc
            }
            if let artist = tiff[kCGImagePropertyTIFFArtist] as? String {
                result.artist = artist
            }
            if let copyright = tiff[kCGImagePropertyTIFFCopyright] as? String {
                result.copyright = copyright
            }
        }

        if let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
            if let caption = iptc[kCGImagePropertyIPTCCaptionAbstract] as? String, result.title == nil {
                result.title = caption
            }
            if let byline = iptc[kCGImagePropertyIPTCByline] as? String, result.artist == nil {
                result.artist = byline
            }
            if let kw = iptc[kCGImagePropertyIPTCKeywords] as? [String] {
                result.keywords = kw
            }
        }

        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let fNumber = exif[kCGImagePropertyExifFNumber] as? Double {
                result.aperture = String(format: "ƒ/%.1f", fNumber)
            }
            if let exposureTime = exif[kCGImagePropertyExifExposureTime] as? Double {
                if exposureTime < 1 {
                    result.shutterSpeed = "1/\(Int(round(1.0 / exposureTime))) s"
                } else {
                    result.shutterSpeed = "\(exposureTime) s"
                }
            }
            if let isoArray = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let iso = isoArray.first {
                result.iso = "ISO \(iso)"
            }
            if let focalLength = exif[kCGImagePropertyExifFocalLength] as? Double {
                result.focalLength = "\(Int(round(focalLength))) mm"
            }
            if let lens = exif[kCGImagePropertyExifLensModel] as? String {
                result.lensModel = lens
            }
            if let flash = exif[kCGImagePropertyExifFlash] as? Int {
                result.flashFired = (flash & 1) != 0
            }
            if let comment = exif[kCGImagePropertyExifUserComment] as? String {
                result.comment = comment
            }
        }
    }

    private static func extractAudioMetadata(from url: URL, into result: inout MediaDetails) async {
        let asset = AVURLAsset(url: url)
        if let duration = try? await asset.load(.duration) {
            let totalSeconds = Int(CMTimeGetSeconds(duration))
            if totalSeconds > 0 {
                let mins = totalSeconds / 60
                let secs = totalSeconds % 60
                result.duration = String(format: "%d:%02d", mins, secs)
            }
        }

        if let tracks = try? await asset.loadTracks(withMediaType: .audio), let track = tracks.first {
            if let formatDescriptions = try? await track.load(.formatDescriptions), let desc = formatDescriptions.first {
                let basic = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee
                if let rate = basic?.mSampleRate {
                    result.sampleRate = String(format: "%.1f kHz", rate / 1000.0)
                }
                if let channels = basic?.mChannelsPerFrame {
                    result.audioChannels = channels == 1 ? "Mono" : (channels == 2 ? "Stereo" : "\(channels) channels")
                }
            }
        }

        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                if let key = item.commonKey?.rawValue {
                    let str = try? await item.load(.stringValue)
                    if key == "title" { result.title = str }
                    else if key == "artist" { result.artist = str }
                    else if key == "albumName" { result.album = str }
                }
            }
        }
    }

    private static func extractVideoMetadata(from url: URL, into result: inout MediaDetails) async {
        let asset = AVURLAsset(url: url)
        if let duration = try? await asset.load(.duration) {
            let totalSeconds = Int(CMTimeGetSeconds(duration))
            if totalSeconds > 0 {
                let mins = totalSeconds / 60
                let secs = totalSeconds % 60
                result.duration = String(format: "%d:%02d", mins, secs)
            }
        }

        if let videoTracks = try? await asset.loadTracks(withMediaType: .video), let track = videoTracks.first {
            if let size = try? await track.load(.naturalSize) {
                result.dimensions = "\(Int(size.width)) × \(Int(size.height))"
            }
            if let fps = try? await track.load(.nominalFrameRate), fps > 0 {
                result.frameRate = String(format: "%.0f fps", fps)
            }
        }

        if let audioTracks = try? await asset.loadTracks(withMediaType: .audio), let track = audioTracks.first {
            if let formatDescriptions = try? await track.load(.formatDescriptions), let desc = formatDescriptions.first {
                let basic = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee
                if let channels = basic?.mChannelsPerFrame {
                    result.audioChannels = channels == 1 ? "Mono" : (channels == 2 ? "Stereo" : "\(channels) channels")
                }
            }
        }
    }
}
