import SwiftUI

/// Progress sheet for long-running file operations (Prompt 10). `Progress`
/// isn't `ObservableObject`, so the view polls it on a short timer.
struct ProgressPanel: View {
    let progress: Progress
    let operationName: String
    let onCancel: () -> Void

    @State private var completed: Int64 = 0
    @State private var total: Int64 = 1
    @State private var isCancelling = false
    @State private var startedAt = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(operationName)
                .font(.headline)
            ProgressView(value: Double(completed), total: Double(max(1, total)))
            Text(statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(isCancelling ? "Cancelling…" : "Cancel") {
                    isCancelling = true
                    onCancel()
                }
                    .disabled(isCancelling)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            completed = progress.completedUnitCount
            total = progress.totalUnitCount
        }
    }

    /// "12.3 MB of 48.1 MB — about 5 s remaining"
    private var statusLine: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let done = formatter.string(fromByteCount: completed)
        let whole = formatter.string(fromByteCount: total)
        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed > 0.5, completed > 0 else {
            return "\(done) of \(whole)"
        }
        let remaining = Double(total - completed) / (Double(completed) / elapsed)
        let eta = remaining.isFinite
            ? Self.etaFormatter.string(from: max(0, remaining)) ?? ""
            : ""
        return "\(done) of \(whole) — about \(eta) remaining"
    }

    private static let etaFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.minute, .second]
        return formatter
    }()
}

#Preview {
    let progress = Progress(totalUnitCount: 100)
    progress.completedUnitCount = 42
    return ProgressPanel(progress: progress, operationName: "Copying Files", onCancel: {})
}
