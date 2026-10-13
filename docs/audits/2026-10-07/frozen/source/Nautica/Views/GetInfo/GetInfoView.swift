import AppKit
import CoreServices
import SwiftUI
import UniformTypeIdentifiers

/// Standalone Finder-style "Get Info" view displaying full metadata,
/// default application selector with "Change All...", and Sharing & Permissions table.
struct GetInfoView: View {
    let targetURL: URL
    var onClose: (() -> Void)?

    @State private var currentURL: URL
    @State private var fileName: String = ""
    @State private var hideExtension: Bool = false
    @State private var isLocked: Bool = false
    @State private var kindDescription: String = ""
    @State private var sizeBytes: Int64? = nil
    @State private var sizeOnDisk: Int64? = nil
    @State private var creationDate: Date? = nil
    @State private var modificationDate: Date? = nil
    @State private var isDirectory: Bool = false
    @State private var ownerName: String = ""
    @State private var groupName: String = ""
    @State private var posixPermissions: Int = 0o644

    // Open With
    @State private var defaultAppURL: URL? = nil
    @State private var candidateApps: [URL] = []
    @State private var showChangeAllConfirmation: Bool = false

    // Section expansions
    @State private var isGeneralExpanded: Bool = true
    @State private var isNameExtensionExpanded: Bool = true
    @State private var isOpenWithExpanded: Bool = true
    @State private var isPermissionsExpanded: Bool = true

    // Tags
    @State private var itemTags: [String] = []
    @State private var newTagInput: String = ""

    // Cloud
    @State private var isCloudExpanded: Bool = true
    @State private var cloudProvider: CloudStorageProvider? = nil
    @State private var cloudStatus: CloudSyncStatus = .notCloud

    private var isCloudItem: Bool {
        cloudStatus != .notCloud || cloudProvider != nil
    }

    // Checksums & Hashes
    @State private var isChecksumsExpanded: Bool = true
    @State private var isComputingChecksums: Bool = false
    @State private var sha256Hash: String? = nil
    @State private var md5Hash: String? = nil
    @State private var verifyInput: String = ""
    @State private var copiedAlgorithm: ChecksumAlgorithm? = nil

    init(targetURL: URL, onClose: (() -> Void)? = nil) {
        self.targetURL = targetURL
        self.onClose = onClose
        _currentURL = State(initialValue: targetURL)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Header: Large Icon + Editable Name + Summary
                headerSection

                Divider()

                // Tags Section
                tagsSection

                Divider()

                // General Section
                DisclosureGroup(isExpanded: $isGeneralExpanded) {
                    generalContent
                        .padding(.top, 6)
                } label: {
                    sectionHeader("General")
                }

                if isCloudItem {
                    Divider()

                    // Cloud Status Section
                    DisclosureGroup(isExpanded: $isCloudExpanded) {
                        cloudContent
                            .padding(.top, 6)
                    } label: {
                        sectionHeader("Cloud Status")
                    }
                }

                Divider()

                // Name & Extension Section
                DisclosureGroup(isExpanded: $isNameExtensionExpanded) {
                    nameExtensionContent
                        .padding(.top, 6)
                } label: {
                    sectionHeader("Name & Extension")
                }

                // Open with (Files only)
                if !isDirectory {
                    Divider()
                    DisclosureGroup(isExpanded: $isOpenWithExpanded) {
                        openWithContent
                            .padding(.top, 6)
                    } label: {
                        sectionHeader("Open with:")
                    }

                    Divider()

                    DisclosureGroup(isExpanded: $isChecksumsExpanded) {
                        checksumsContent
                            .padding(.top, 6)
                    } label: {
                        sectionHeader("Checksums & Hashes")
                    }
                }

                Divider()

                // Sharing & Permissions
                DisclosureGroup(isExpanded: $isPermissionsExpanded) {
                    permissionsContent
                        .padding(.top, 6)
                } label: {
                    sectionHeader("Sharing & Permissions:")
                }
            }
            .padding(16)
        }
        .frame(minWidth: 340, idealWidth: 380, maxWidth: 460, minHeight: 450, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadMetadata()
        }
        .confirmationDialog(
            "Change all similar documents?",
            isPresented: $showChangeAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Continue") {
                applyChangeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let defaultAppURL {
                let appName = defaultAppURL.deletingPathExtension().lastPathComponent
                let ext = currentURL.pathExtension
                Text("Are you sure you want to change all similar documents to open with the application “\(appName)”?\n\nThis change will apply to all documents with extension “.\(ext)”.")
            } else {
                Text("Change default application for this file type.")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 14) {
            CustomIconView(url: currentURL, onIconChanged: {
                loadMetadata()
            })
            .frame(width: 64, height: 64)
            .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
            .help("Click to select icon. Press ⌘C to copy, ⌘V to paste custom icon, Delete to revert, or drag an image here.")

            VStack(alignment: .leading, spacing: 4) {
                TextField("File Name", text: $fileName, onCommit: commitRename)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)

                if let sizeBytes {
                    Text(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let modificationDate {
                    Text("Modified: \(modificationDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - General Content

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            infoRow(label: "Kind:", value: kindDescription.isEmpty ? (isDirectory ? "Folder" : "Document") : kindDescription)

            if let sizeBytes {
                let formattedBytes = NumberFormatter.localizedString(from: NSNumber(value: sizeBytes), number: .decimal)
                let diskFormatted = sizeOnDisk != nil ? ByteCountFormatter.string(fromByteCount: sizeOnDisk!, countStyle: .file) : ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
                infoRow(label: "Size:", value: "\(diskFormatted) (\(formattedBytes) bytes)")
            }

            HStack(alignment: .top, spacing: 8) {
                Text("Where:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(currentURL.deletingLastPathComponent().path)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)

                    Button("Show in Nautica") {
                        NSWorkspace.shared.activateFileViewerSelecting([currentURL])
                    }
                    .buttonStyle(.link)
                    .font(.caption2)
                }
            }

            if let creationDate {
                infoRow(label: "Created:", value: creationDate.formatted(date: .long, time: .standard))
            }
            if let modificationDate {
                infoRow(label: "Modified:", value: modificationDate.formatted(date: .long, time: .standard))
            }

            HStack {
                Toggle("Locked", isOn: $isLocked)
                    .font(.system(size: 11))
                    .onChange(of: isLocked) { _, newValue in
                        updateLockStatus(newValue)
                    }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Cloud Content

    private var cloudContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let cloudProvider {
                    Image(systemName: CloudStorageService.systemImage(for: cloudProvider))
                        .font(.system(size: 15))
                        .foregroundStyle(Color.accentColor)
                    Text(CloudStorageService.formatDisplayName(for: cloudProvider.rawValue, provider: cloudProvider))
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Image(systemName: "icloud")
                        .font(.system(size: 15))
                    Text("Cloud Storage")
                        .font(.system(size: 12, weight: .medium))
                }
                Spacer()
                cloudStatusBadge
            }

            Text(cloudStatusDescription)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if cloudStatus == .onlineOnly {
                    Button {
                        downloadCloudItem()
                    } label: {
                        Label("Download Now", systemImage: "icloud.and.arrow.down")
                    }
                    .controlSize(.small)
                } else if cloudStatus == .downloaded {
                    Button {
                        evictCloudItem()
                    } label: {
                        Label("Remove Download (Free Up Space)", systemImage: "icloud.slash")
                    }
                    .controlSize(.small)
                } else if cloudStatus == .downloading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Downloading item…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private var cloudStatusBadge: some View {
        HStack(spacing: 4) {
            switch cloudStatus {
            case .onlineOnly:
                Image(systemName: "icloud.and.arrow.down.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("In Cloud")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            case .downloading:
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.blue)
                Text("Downloading")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.blue)
            case .conflict:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange)
                Text("Sync Conflict")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.orange)
            case .downloaded:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.green)
                Text("Downloaded")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.primary)
            case .notCloud:
                EmptyView()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }

    private var cloudStatusDescription: String {
        switch cloudStatus {
        case .onlineOnly:
            return "This item is stored in the cloud (dataless placeholder). It will be downloaded automatically when opened, or you can download it now for offline access."
        case .downloaded:
            return "This item is locally downloaded and cached on your Mac. It is available offline at full speed."
        case .downloading:
            return "This item is currently being transferred to your local disk from the cloud provider."
        case .conflict:
            return "There is a synchronization conflict between your local changes and the cloud version."
        case .notCloud:
            return "Local file on your Mac."
        }
    }

    private func downloadCloudItem() {
        Task {
            try? await CloudStorageService.downloadItem(at: currentURL)
            await MainActor.run { loadMetadata() }
        }
    }

    private func evictCloudItem() {
        Task {
            try? await CloudStorageService.evictItem(at: currentURL)
            await MainActor.run { loadMetadata() }
        }
    }

    // MARK: - Name & Extension Content

    private var nameExtensionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $fileName, onCommit: commitRename)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            Toggle("Hide extension", isOn: $hideExtension)
                .font(.system(size: 11))
                .onChange(of: hideExtension) { _, newValue in
                    updateHideExtension(newValue)
                }
        }
    }

    // MARK: - Open With Content

    private var openWithContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let defaultAppURL {
                    let appIcon = NSWorkspace.shared.icon(forFile: defaultAppURL.path)
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 20, height: 20)
                }

                Picker("", selection: $defaultAppURL) {
                    ForEach(candidateApps, id: \.self) { app in
                        Text(app.deletingPathExtension().lastPathComponent)
                            .tag(Optional(app))
                    }
                }
                .labelsHidden()
            }

            Text("Use this application to open all documents like this one.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button("Change All…") {
                showChangeAllConfirmation = true
            }
            .controlSize(.small)
        }
    }

    // MARK: - Permissions Content

    private var permissionsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            let accessSummary = currentAccessSummary()
            Text("You have \(accessSummary) access")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                HStack {
                    Text("Name")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Privilege")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.quaternaryLabelColor).opacity(0.1))

                Divider()

                // Owner Row
                permissionRow(
                    name: "\(ownerName.isEmpty ? "Owner" : ownerName) (Me)",
                    icon: "person.fill",
                    mode: (posixPermissions >> 6) & 0o7,
                    onChange: { newMode in updatePermissions(shift: 6, mode: newMode) }
                )

                Divider()

                // Group Row
                permissionRow(
                    name: groupName.isEmpty ? "staff" : groupName,
                    icon: "person.2.fill",
                    mode: (posixPermissions >> 3) & 0o7,
                    onChange: { newMode in updatePermissions(shift: 3, mode: newMode) }
                )

                Divider()

                // Everyone Row
                permissionRow(
                    name: "everyone",
                    icon: "globe",
                    mode: posixPermissions & 0o7,
                    onChange: { newMode in updatePermissions(shift: 0, mode: newMode) }
                )
            }
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
        }
    }

    private func permissionRow(name: String, icon: String, mode: Int, onChange: @escaping (Int) -> Void) -> some View {
        HStack {
            Label(name, systemImage: icon)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer()

            Picker("", selection: Binding(
                get: { privilegeFromMode(mode) },
                set: { newPrivilege in onChange(modeFromPrivilege(newPrivilege)) }
            )) {
                Text("Read & Write").tag(Privilege.readWrite)
                Text("Read only").tag(Privilege.readOnly)
                Text("No Access").tag(Privilege.noAccess)
            }
            .labelsHidden()
            .controlSize(.mini)
            .frame(width: 120)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Checksums Content

    private var checksumsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isComputingChecksums {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Calculating SHA-256 and MD5 hashes...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                // SHA-256 Row
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("SHA-256:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let hash = sha256Hash {
                            Button {
                                copyToClipboard(text: hash, algorithm: .sha256)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: copiedAlgorithm == .sha256 ? "checkmark" : "doc.on.doc")
                                    Text(copiedAlgorithm == .sha256 ? "Copied" : "Copy")
                                }
                                .font(.system(size: 10))
                                .foregroundStyle(copiedAlgorithm == .sha256 ? Color.green : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Copy SHA-256 Checksum")
                        }
                    }
                    Text(sha256Hash ?? "—")
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                // MD5 Row
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("MD5:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let hash = md5Hash {
                            Button {
                                copyToClipboard(text: hash, algorithm: .md5)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: copiedAlgorithm == .md5 ? "checkmark" : "doc.on.doc")
                                    Text(copiedAlgorithm == .md5 ? "Copied" : "Copy")
                                }
                                .font(.system(size: 10))
                                .foregroundStyle(copiedAlgorithm == .md5 ? Color.green : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Copy MD5 Checksum")
                        }
                    }
                    Text(md5Hash ?? "—")
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                }

                Divider()

                // Verify Hash Input Field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Verify Hash:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField("Paste expected checksum…", text: $verifyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))

                    verifyStatusBadge
                }
            }
        }
        .onAppear {
            computeChecksums()
        }
    }

    @ViewBuilder
    private var verifyStatusBadge: some View {
        let trimmed = ChecksumService.normalize(hash: verifyInput)
        if trimmed.isEmpty {
            EmptyView()
        } else {
            let matchesSHA256 = (sha256Hash != nil) && (ChecksumService.normalize(hash: sha256Hash!) == trimmed)
            let matchesMD5 = (md5Hash != nil) && (ChecksumService.normalize(hash: md5Hash!) == trimmed)

            if matchesSHA256 || matchesMD5 {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text(matchesSHA256 ? "Verified: Exact SHA-256 match!" : "Verified: Exact MD5 match!")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                }
                .padding(.top, 2)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text("Checksum mismatch (corrupted or altered)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.red)
                }
                .padding(.top, 2)
            }
        }
    }

    private func computeChecksums() {
        guard !isDirectory, sha256Hash == nil, !isComputingChecksums else { return }
        isComputingChecksums = true
        Task {
            let hashes = try? await ChecksumService.shared.computeHashes(
                url: currentURL,
                algorithms: [.sha256, .md5]
            )
            await MainActor.run {
                self.sha256Hash = hashes?[.sha256]
                self.md5Hash = hashes?[.md5]
                self.isComputingChecksums = false
            }
        }
    }

    private func copyToClipboard(text: String, algorithm: ChecksumAlgorithm) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedAlgorithm = algorithm
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                if self.copiedAlgorithm == algorithm {
                    self.copiedAlgorithm = nil
                }
            }
        }
    }

    // MARK: - Helpers & Data Loading

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.primary)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadMetadata() {
        fileName = currentURL.lastPathComponent

        // Values from resourceValues
        if let res = try? currentURL.resourceValues(forKeys: [
            .isDirectoryKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .hasHiddenExtensionKey,
            .isUserImmutableKey,
            .localizedTypeDescriptionKey,
            .contentTypeKey,
            .tagNamesKey
        ]) {
            isDirectory = res.isDirectory ?? false
            sizeBytes = Int64(res.fileSize ?? 0)
            sizeOnDisk = Int64(res.totalFileAllocatedSize ?? 0)
            creationDate = res.creationDate
            modificationDate = res.contentModificationDate
            hideExtension = res.hasHiddenExtension ?? false
            isLocked = res.isUserImmutable ?? false
            kindDescription = res.localizedTypeDescription ?? ""
            itemTags = res.tagNames ?? []

            // Open with applications
            if !isDirectory, let uti = res.contentType {
                loadCandidateApplications(for: uti)
            }
        }

        // Cloud status & provider
        cloudProvider = CloudStorageService.provider(for: currentURL)
        cloudStatus = CloudStorageService.cloudStatus(for: currentURL)

        // POSIX attributes
        if let attrs = try? FileManager.default.attributesOfItem(atPath: currentURL.path) {
            ownerName = (attrs[.ownerAccountName] as? String) ?? NSUserName()
            groupName = (attrs[.groupOwnerAccountName] as? String) ?? "staff"
            if let perms = attrs[.posixPermissions] as? NSNumber {
                posixPermissions = perms.intValue
            }
        }
    }

    private func loadCandidateApplications(for uti: UTType) {
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: uti)
        candidateApps = apps
        if let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: currentURL) {
            defaultAppURL = defaultApp
            if !candidateApps.contains(defaultApp) {
                candidateApps.insert(defaultApp, at: 0)
            }
        } else if let first = apps.first {
            defaultAppURL = first
        }
    }

    private func commitRename() {
        guard !fileName.isEmpty, fileName != currentURL.lastPathComponent else { return }
        let newURL = currentURL.deletingLastPathComponent().appendingPathComponent(fileName)
        do {
            try FileManager.default.moveItem(at: currentURL, to: newURL)
            currentURL = newURL
            loadMetadata()
        } catch {
            fileName = currentURL.lastPathComponent
        }
    }

    private func updateHideExtension(_ hide: Bool) {
        var values = URLResourceValues()
        values.hasHiddenExtension = hide
        try? currentURL.setResourceValues(values)
    }

    private func updateLockStatus(_ locked: Bool) {
        var values = URLResourceValues()
        values.isUserImmutable = locked
        try? currentURL.setResourceValues(values)
    }

    private func applyChangeAll() {
        guard let defaultAppURL, let uti = try? currentURL.resourceValues(forKeys: [.contentTypeKey]).contentType else { return }
        if let bundle = Bundle(url: defaultAppURL), let bundleID = bundle.bundleIdentifier {
            let status = LSSetDefaultRoleHandlerForContentType(uti.identifier as CFString, .all, bundleID as CFString)
            if status == noErr {
                loadMetadata()
            }
        }
    }

    private enum Privilege: Hashable {
        case readWrite
        case readOnly
        case noAccess
    }

    private func privilegeFromMode(_ mode: Int) -> Privilege {
        if (mode & 0o6) == 0o6 { return .readWrite }
        if (mode & 0o4) == 0o4 { return .readOnly }
        return .noAccess
    }

    private func modeFromPrivilege(_ privilege: Privilege) -> Int {
        switch privilege {
        case .readWrite: return 0o6
        case .readOnly: return 0o4
        case .noAccess: return 0o0
        }
    }

    private func currentAccessSummary() -> String {
        let ownerMode = (posixPermissions >> 6) & 0o7
        switch privilegeFromMode(ownerMode) {
        case .readWrite: return "Read & Write"
        case .readOnly: return "Read only"
        case .noAccess: return "no"
        }
    }

    private func updatePermissions(shift: Int, mode: Int) {
        let mask = ~(0o7 << shift)
        let newPermissions = (posixPermissions & mask) | ((mode & 0o7) << shift)
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: newPermissions)],
                ofItemAtPath: currentURL.path
            )
            posixPermissions = newPermissions
        } catch {
            // Revert on failure
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Tags:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(TagColor.allCases) { color in
                        let hasColor = itemTags.contains { tag in
                            FileTagInfo(rawName: tag).color == color
                        }
                        Button {
                            toggleColor(color)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 14, height: 14)
                                if hasColor {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Toggle \(color.name) (^\(color.shortcutNumber))")
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(itemTags, id: \.self) { tag in
                        let info = FileTagInfo(rawName: tag)
                        HStack(spacing: 4) {
                            if let color = info.color {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 8, height: 8)
                            }
                            Text(info.displayName)
                                .font(.system(size: 11))
                            Button {
                                removeTag(tag)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                    }

                    HStack(spacing: 4) {
                        TextField("Add tag…", text: $newTagInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .onSubmit {
                                addTag()
                            }
                        if !newTagInput.isEmpty {
                            Button {
                                addTag()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(minWidth: 70, maxWidth: 120)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
                }
            }
        }
    }

    private func toggleColor(_ color: TagColor) {
        Task {
            try? await TagService.shared.toggleColorTag(color, for: [currentURL])
            await MainActor.run {
                let values = try? currentURL.resourceValues(forKeys: [.tagNamesKey])
                itemTags = values?.tagNames ?? []
            }
        }
    }

    private func removeTag(_ tag: String) {
        var updated = itemTags
        updated.removeAll { $0 == tag }
        itemTags = updated
        Task {
            try? await TagService.shared.setTags(updated, for: currentURL)
        }
    }

    private func addTag() {
        let trimmed = newTagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        newTagInput = ""
        var updated = itemTags
        if !updated.contains(trimmed) {
            updated.append(trimmed)
            itemTags = updated
            Task {
                try? await TagService.shared.setTags(updated, for: currentURL)
            }
        }
    }
}
