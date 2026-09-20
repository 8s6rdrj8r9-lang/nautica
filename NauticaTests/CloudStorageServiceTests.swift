import XCTest
@testable import Nautica

final class CloudStorageServiceTests: XCTestCase {

    func testProviderDetection() {
        XCTAssertEqual(CloudStorageService.provider(for: "OneDrive-Personal"), .oneDrive)
        XCTAssertEqual(CloudStorageService.provider(for: "OneDrive-AcmeCorp"), .oneDrive)
        XCTAssertEqual(CloudStorageService.provider(for: "OneDrive"), .oneDrive)

        XCTAssertEqual(CloudStorageService.provider(for: "GoogleDrive-user@gmail.com"), .googleDrive)
        XCTAssertEqual(CloudStorageService.provider(for: "Google Drive"), .googleDrive)
        XCTAssertEqual(CloudStorageService.provider(for: "googledrive"), .googleDrive)

        XCTAssertEqual(CloudStorageService.provider(for: "Dropbox"), .dropbox)
        XCTAssertEqual(CloudStorageService.provider(for: "Dropbox (Personal)"), .dropbox)
        XCTAssertEqual(CloudStorageService.provider(for: "dropbox"), .dropbox)

        XCTAssertEqual(CloudStorageService.provider(for: "Box-Box"), .box)
        XCTAssertEqual(CloudStorageService.provider(for: "Nextcloud-files"), .generic)

        let icloudURL = URL(fileURLWithPath: "/Users/test/Library/Mobile Documents/com~apple~CloudDocs")
        XCTAssertEqual(CloudStorageService.provider(for: "CloudDocs", url: icloudURL), .iCloud)
    }

    func testDisplayNameFormatting() {
        XCTAssertEqual(
            CloudStorageService.formatDisplayName(for: "OneDrive-Personal", provider: .oneDrive),
            "OneDrive (Personal)"
        )
        XCTAssertEqual(
            CloudStorageService.formatDisplayName(for: "OneDrive-Contoso", provider: .oneDrive),
            "OneDrive (Contoso)"
        )
        XCTAssertEqual(
            CloudStorageService.formatDisplayName(for: "OneDrive", provider: .oneDrive),
            "OneDrive"
        )

        XCTAssertEqual(
            CloudStorageService.formatDisplayName(for: "GoogleDrive-user@test.org", provider: .googleDrive),
            "Google Drive (user@test.org)"
        )
        XCTAssertEqual(
            CloudStorageService.formatDisplayName(for: "Google Drive", provider: .googleDrive),
            "Google Drive"
        )

        XCTAssertEqual(
            CloudStorageService.formatDisplayName(for: "Dropbox", provider: .dropbox),
            "Dropbox"
        )
        XCTAssertEqual(
            CloudStorageService.formatDisplayName(for: "Dropbox (Work)", provider: .dropbox),
            "Dropbox (Work)"
        )

        XCTAssertEqual(
            CloudStorageService.formatDisplayName(for: "Box-Box", provider: .box),
            "Box"
        )

        XCTAssertEqual(
            CloudStorageService.formatDisplayName(for: "CustomCloud", provider: .generic),
            "CustomCloud"
        )
    }

    func testSystemImages() {
        XCTAssertEqual(CloudStorageService.systemImage(for: .iCloud), "icloud")
        XCTAssertEqual(CloudStorageService.systemImage(for: .oneDrive), "cloud.fill")
        XCTAssertEqual(CloudStorageService.systemImage(for: .googleDrive), "externaldrive.badge.icloud")
        XCTAssertEqual(CloudStorageService.systemImage(for: .dropbox), "shippingbox.fill")
        XCTAssertEqual(CloudStorageService.systemImage(for: .box), "shippingbox")
        XCTAssertEqual(CloudStorageService.systemImage(for: .generic), "cloud")
    }

    func testParseCloudFolderCreatesSidebarItem() {
        let oneDriveURL = URL(fileURLWithPath: "/Users/test/Library/CloudStorage/OneDrive-Personal")
        let item = CloudStorageService.parseCloudFolder(name: "OneDrive-Personal", url: oneDriveURL)

        XCTAssertEqual(item.name, "OneDrive (Personal)")
        XCTAssertEqual(item.url, oneDriveURL)
        XCTAssertEqual(item.customSystemImage, "cloud.fill")

        let googleURL = URL(fileURLWithPath: "/Users/test/Library/CloudStorage/GoogleDrive-me@example.com")
        let googleItem = CloudStorageService.parseCloudFolder(name: "GoogleDrive-me@example.com", url: googleURL)
        XCTAssertEqual(googleItem.name, "Google Drive (me@example.com)")
        XCTAssertEqual(googleItem.customSystemImage, "externaldrive.badge.icloud")

        let dropboxURL = URL(fileURLWithPath: "/Users/test/Dropbox")
        let dropboxItem = CloudStorageService.parseCloudFolder(name: "Dropbox", url: dropboxURL)
        XCTAssertEqual(dropboxItem.name, "Dropbox")
        XCTAssertEqual(dropboxItem.customSystemImage, "shippingbox.fill")
    }

    func testCloudSyncStatusAndFileItemCloudProperties() {
        let normalItem = FileItem(
            url: URL(fileURLWithPath: "/Users/test/Documents/report.pdf"),
            name: "report.pdf",
            isDirectory: false,
            size: 1024,
            modificationDate: nil,
            creationDate: nil,
            isHidden: false,
            kind: "PDF Document"
        )
        XCTAssertFalse(normalItem.isCloudItem)
        XCTAssertEqual(normalItem.cloudStatus, .notCloud)

        let onlineOnlyItem = FileItem(
            url: URL(fileURLWithPath: "/Users/test/Library/CloudStorage/OneDrive-Personal/video.mov"),
            name: "video.mov",
            isDirectory: false,
            size: 5_000_000,
            modificationDate: nil,
            creationDate: nil,
            isHidden: false,
            kind: "QuickTime Movie",
            cloudStatus: .onlineOnly
        )
        XCTAssertTrue(onlineOnlyItem.isCloudItem)
        XCTAssertEqual(onlineOnlyItem.cloudStatus, .onlineOnly)

        let downloadedItem = FileItem(
            url: URL(fileURLWithPath: "/Users/test/Library/CloudStorage/Dropbox/notes.txt"),
            name: "notes.txt",
            isDirectory: false,
            size: 200,
            modificationDate: nil,
            creationDate: nil,
            isHidden: false,
            kind: "Text Document",
            cloudStatus: .downloaded
        )
        XCTAssertTrue(downloadedItem.isCloudItem)
        XCTAssertEqual(downloadedItem.cloudStatus, .downloaded)
    }
}
