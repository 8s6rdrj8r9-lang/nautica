import AppKit
import SwiftUI

/// Modal sheet presented when one or more file conflicts occur during a transfer.
struct ConflictResolutionSheet: View {
    @Bindable var model: ConflictResolutionModel
    var onComplete: ([URL: ConflictResolutionChoice]) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            if let conflict = model.currentConflict {
                // Header
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("An item named “\(conflict.fileName)” already exists in this location.")
                            .font(.headline)
                            .lineLimit(2)

                        Text("Do you want to replace it with the one you’re \(model.isMove ? "moving" : "copying")?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // Side-by-side comparison cards
                HStack(spacing: 16) {
                    fileCard(
                        title: "Existing Item",
                        badgeColor: .secondary,
                        url: conflict.destinationURL,
                        date: conflict.destinationDate,
                        size: conflict.destinationSize
                    )

                    fileCard(
                        title: isNewer(source: conflict.sourceDate, destination: conflict.destinationDate) ? "Newer Item" : "Older Item",
                        badgeColor: .blue,
                        url: conflict.sourceURL,
                        date: conflict.sourceDate,
                        size: conflict.sourceSize
                    )
                }

                if model.remainingCount > 1 {
                    HStack {
                        Toggle("Apply to all (\(model.remainingCount) conflicts)", isOn: $model.applyToAll)
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(.top, 4)
                }

                Divider()

                // Actions: Stop / Keep Both / Replace
                HStack(spacing: 12) {
                    Button("Stop") {
                        model.resolveCurrent(with: .stop)
                        onCancel()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button("Keep Both") {
                        model.resolveCurrent(with: .keepBoth)
                        checkFinished()
                    }

                    Button("Replace") {
                        model.resolveCurrent(with: .replace)
                        checkFinished()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                Text("Resolving conflicts…")
                    .font(.headline)
                    .onAppear {
                        onComplete(model.resolutions)
                    }
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func fileCard(title: String, badgeColor: Color, url: URL, date: Date?, size: Int64?) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(badgeColor)

            let icon = NSWorkspace.shared.icon(forFile: url.path)
            Image(nsImage: icon)
                .resizable()
                .frame(width: 48, height: 48)

            VStack(spacing: 2) {
                if let size {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                if let date {
                    Text("Modified: \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }

    private func isNewer(source: Date?, destination: Date?) -> Bool {
        guard let source, let destination else { return false }
        return source > destination
    }

    private func checkFinished() {
        if model.isFinished {
            onComplete(model.resolutions)
        }
    }
}
