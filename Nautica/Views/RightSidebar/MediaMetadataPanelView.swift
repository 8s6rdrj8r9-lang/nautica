import SwiftUI
import AppKit
import ImageIO
import AVFoundation

/// Media metadata extracted from images, audio, or video.
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

    enum MediaType {
        case image
        case audio
        case video
        case other
    }
}

/// Right sidebar panel displaying deep EXIF, camera, audio, and video specifications.
struct MediaMetadataPanelView: View {
    let selectedItem: FileItem?
    var onQuickLook: () -> Void

    @State private var details: MediaDetails?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Media & EXIF", systemImage: "camera")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if let selectedItem {
                if isLoading {
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Text("Reading media properties…").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let details, details.mediaType != .other {
                    mediaContentView(item: selectedItem, details: details)
                } else {
                    nonMediaSelectedView(selectedItem)
                }
            } else {
                emptySelectionView
            }
        }
        .task(id: selectedItem?.url) {
            loadMediaDetails()
        }
    }

    // MARK: - Subviews

    private func mediaContentView(item: FileItem, details: MediaDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header Thumbnail
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
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)

                // Quick Look Action
                Button(action: onQuickLook) {
                    Label("Preview Media", systemImage: "eye")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)

                Divider()

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
                    if details.title != nil || details.artist != nil || details.album != nil {
                        metadataSection("Track Information") {
                            if let t = details.title { metaRow("Title", t) }
                            if let a = details.artist { metaRow("Artist", a) }
                            if let alb = details.album { metaRow("Album", alb) }
                        }
                        Divider()
                    }

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

    private var emptySelectionView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text("No File Selected")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Select an image, photo, song, or video to view technical EXIF and stream properties.")
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

            Text("This file does not contain media or EXIF streams.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
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

        let url = item.url
        let ext = url.pathExtension.lowercased()
        let imageExtensions = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "raw", "dng", "cr2", "nef", "webp", "gif"]
        let audioExtensions = ["mp3", "m4a", "wav", "flac", "aac", "aiff", "alac"]
        let videoExtensions = ["mp4", "mov", "m4v", "mkv", "avi", "webm"]

        isLoading = true

        Task.detached(priority: .userInitiated) {
            var result = MediaDetails()

            if imageExtensions.contains(ext) {
                result.mediaType = .image
                Self.extractImageMetadata(from: url, into: &result)
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
