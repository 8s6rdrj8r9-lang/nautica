import SwiftUI
import AppKit

/// Read-only Hex Inspector panel for examining raw binary bytes, ASCII decodes,
/// and file structures with chunked virtual paging and byte searching.
struct HexViewerPanelView: View {
    let selectedItem: FileItem?

    @State private var currentOffset: Int64 = 0
    private let pageSize: Int = 1024 // 1 KB per page
    @State private var pageData: Data = Data()
    @State private var totalFileSize: Int64 = 0
    @State private var jumpOffsetInput: String = ""
    @State private var searchQuery: String = ""
    @State private var searchMatchOffset: Int64? = nil
    @State private var errorMessage: String? = nil

    private var totalPages: Int {
        guard totalFileSize > 0 else { return 1 }
        return Int((totalFileSize + Int64(pageSize) - 1) / Int64(pageSize))
    }

    private var currentPageIndex: Int {
        Int(currentOffset / Int64(pageSize)) + 1
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Hex Inspector", systemImage: "number.square")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()

                if !pageData.isEmpty {
                    Button(action: copyHexToClipboard) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Copy Hex Dump to Clipboard")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if let item = selectedItem, !item.isDirectory {
                // File info bar
                HStack(spacing: 8) {
                    Image(systemName: "doc")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Text("\(item.formattedSize) • \(totalFileSize) bytes")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Search & Jump toolbar
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)

                        TextField("Find text or hex (e.g. 'PNG' or '89 50')...", text: $searchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .onSubmit { performSearch() }

                        if !searchQuery.isEmpty {
                            Button(action: { searchQuery = ""; searchMatchOffset = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }

                        Button("Find", action: performSearch)
                            .font(.system(size: 10))
                            .controlSize(.mini)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                    HStack(spacing: 6) {
                        Text("Jump:")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        TextField("0x0000", text: $jumpOffsetInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 70)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .onSubmit { jumpToEnteredOffset() }

                        Button("Go", action: jumpToEnteredOffset)
                            .font(.system(size: 10))
                            .controlSize(.mini)

                        Spacer()

                        // Paging buttons
                        Button(action: prevPage) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10))
                        }
                        .disabled(currentOffset == 0)
                        .buttonStyle(.plain)

                        Text("P \(currentPageIndex)/\(max(1, totalPages))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Button(action: nextPage) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                        }
                        .disabled(currentOffset + Int64(pageSize) >= totalFileSize)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

                Divider()

                // Hex dump view
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(0..<rowsCount, id: \.self) { rowIndex in
                            hexRowView(forRow: rowIndex)
                        }
                    }
                    .padding(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))

            } else {
                // Empty state
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "number.square")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text(selectedItem?.isDirectory == true ? "Folders Have No Raw Bytes" : "No File Selected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(selectedItem?.isDirectory == true ? "Select any file to view its raw binary dump and ASCII translation." : "Select a file to inspect its raw binary contents.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: selectedItem?.id) { _, _ in
            loadCurrentFile()
        }
        .onAppear {
            loadCurrentFile()
        }
    }

    private var rowsCount: Int {
        (pageData.count + 15) / 16
    }

    @ViewBuilder
    private func hexRowView(forRow rowIndex: Int) -> some View {
        let rowStart = rowIndex * 16
        let rowEnd = min(rowStart + 16, pageData.count)
        let rowBytes = pageData.subdata(in: rowStart..<rowEnd)
        let rowAbsoluteOffset = currentOffset + Int64(rowStart)

        HStack(spacing: 8) {
            // Offset column
            Text(String(format: "%08X", rowAbsoluteOffset))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.accentColor)

            // Hex Bytes column
            Text(formatHexBytes(rowBytes))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)

            // ASCII column
            Text(formatASCII(rowBytes))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func formatHexBytes(_ data: Data) -> String {
        var str = ""
        for (i, byte) in data.enumerated() {
            str += String(format: "%02X ", byte)
            if i == 7 {
                str += " "
            }
        }
        if data.count < 16 {
            let padding = (16 - data.count) * 3 + (data.count <= 8 ? 1 : 0)
            str += String(repeating: " ", count: padding)
        }
        return str
    }

    private func formatASCII(_ data: Data) -> String {
        var str = ""
        for byte in data {
            if byte >= 32 && byte <= 126 {
                str.append(Character(UnicodeScalar(byte)))
            } else {
                str.append(".")
            }
        }
        return str
    }

    private func loadCurrentFile() {
        guard let item = selectedItem, !item.isDirectory else {
            pageData = Data()
            totalFileSize = 0
            currentOffset = 0
            return
        }

        let path = item.url.path
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int64 {
            totalFileSize = size
        } else {
            totalFileSize = item.size ?? 0
        }

        currentOffset = 0
        readPage(at: 0)
    }

    private func readPage(at offset: Int64) {
        guard let item = selectedItem, !item.isDirectory else { return }
        guard let handle = try? FileHandle(forReadingFrom: item.url) else { return }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: UInt64(max(0, offset)))
            pageData = handle.readData(ofLength: pageSize)
            currentOffset = offset
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prevPage() {
        let newOffset = max(0, currentOffset - Int64(pageSize))
        readPage(at: newOffset)
    }

    private func nextPage() {
        guard currentOffset + Int64(pageSize) < totalFileSize else { return }
        let newOffset = currentOffset + Int64(pageSize)
        readPage(at: newOffset)
    }

    private func jumpToEnteredOffset() {
        let text = jumpOffsetInput.trimmingCharacters(in: .whitespacesAndNewlines)
        var offset: Int64 = 0
        if text.lowercased().hasPrefix("0x") {
            let hex = String(text.dropFirst(2))
            offset = Int64(hex, radix: 16) ?? 0
        } else {
            offset = Int64(text) ?? 0
        }

        offset = max(0, min(offset, max(0, totalFileSize - 1)))
        let alignedOffset = (offset / 16) * 16
        readPage(at: alignedOffset)
    }

    private func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let item = selectedItem, !item.isDirectory else { return }

        guard let handle = try? FileHandle(forReadingFrom: item.url) else { return }
        defer { try? handle.close() }

        var targetData: Data? = nil
        // Check if query is hex (e.g. "89 50 4E")
        let cleanedHex = query.replacingOccurrences(of: " ", with: "")
        if cleanedHex.count % 2 == 0 && cleanedHex.allSatisfy({ $0.isHexDigit }) {
            var data = Data()
            var index = cleanedHex.startIndex
            while index < cleanedHex.endIndex {
                let nextIndex = cleanedHex.index(index, offsetBy: 2)
                let byteStr = String(cleanedHex[index..<nextIndex])
                if let byte = UInt8(byteStr, radix: 16) {
                    data.append(byte)
                }
                index = nextIndex
            }
            targetData = data
        } else if let stringData = query.data(using: .utf8) {
            targetData = stringData
        }

        guard let needle = targetData, !needle.isEmpty else { return }

        // Scan file in chunks
        let chunkSize = 64 * 1024
        var scanOffset: Int64 = currentOffset + 1
        if scanOffset >= totalFileSize { scanOffset = 0 }

        while scanOffset < totalFileSize {
            try? handle.seek(toOffset: UInt64(scanOffset))
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }

            if let range = chunk.range(of: needle) {
                let foundOffset = scanOffset + Int64(range.lowerBound)
                searchMatchOffset = foundOffset
                let alignedOffset = (foundOffset / 16) * 16
                readPage(at: alignedOffset)
                return
            }
            scanOffset += Int64(chunk.count - needle.count + 1)
        }
    }

    private func copyHexToClipboard() {
        var dump = ""
        for rowIndex in 0..<rowsCount {
            let rowStart = rowIndex * 16
            let rowEnd = min(rowStart + 16, pageData.count)
            let rowBytes = pageData.subdata(in: rowStart..<rowEnd)
            let rowAbsoluteOffset = currentOffset + Int64(rowStart)
            dump += String(format: "%08X:  %-48s  |%s|\n", rowAbsoluteOffset, (formatHexBytes(rowBytes) as NSString).utf8String ?? "", (formatASCII(rowBytes) as NSString).utf8String ?? "")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(dump, forType: .string)
    }
}
