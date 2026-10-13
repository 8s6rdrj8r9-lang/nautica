import SwiftUI
import AppKit

/// Modal sheet displaying comprehensive diagnostic health reports for encrypted vaults.
struct VaultHealthSheet: View {
    @Environment(\.dismiss) private var dismiss

    let vaultURL: URL

    @State private var report: VaultDiagnosticsService.VaultHealthReport? = nil
    @State private var isLoading: Bool = true
    @State private var isRepairing: Bool = false
    @State private var repairResult: String? = nil

    private var vaultName: String {
        vaultURL.deletingPathExtension().lastPathComponent
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Diagnosing container structure & cryptographic headers…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else if let report {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        statusBanner(report: report)
                        metricsSection(report: report)
                        logsSection(report: report)

                        if let res = repairResult {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Repair Output")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                Text(res)
                                    .font(.system(size: 10, design: .monospaced))
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(NSColor.textBackgroundColor))
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .padding(16)
                }
            }

            Divider()
            footerView
        }
        .frame(width: 500, height: 520)
        .task {
            await runDiagnostics()
        }
    }

    @ViewBuilder
    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "stethoscope")
                .font(.system(size: 28))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Vault Health & Diagnostics")
                    .font(.headline)
                Text(vaultName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func statusBanner(report: VaultDiagnosticsService.VaultHealthReport) -> some View {
        HStack(spacing: 12) {
            Image(systemName: report.status.sfSymbol)
                .font(.system(size: 28))
                .foregroundStyle(statusColor(for: report.status))

            VStack(alignment: .leading, spacing: 2) {
                Text(report.status.rawValue)
                    .font(.headline)
                    .foregroundStyle(statusColor(for: report.status))
                Text(report.summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(statusColor(for: report.status).opacity(0.1))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func metricsSection(report: VaultDiagnosticsService.VaultHealthReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Container Properties")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                metricCard(title: "Size on Disk", value: ByteCountFormatter.string(fromByteCount: report.actualDiskSizeBytes, countStyle: .file))
                metricCard(title: "Capacity Quota", value: ByteCountFormatter.string(fromByteCount: report.virtualCapacityBytes, countStyle: .file))
                metricCard(title: "Sparse Bands", value: report.bandCount > 0 ? "\(report.bandCount) bands" : "Single image")
                metricCard(title: "Encryption", value: report.encryptionType)
            }
        }
    }

    @ViewBuilder
    private func metricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }

    @ViewBuilder
    private func logsSection(report: VaultDiagnosticsService.VaultHealthReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Diagnostic Log")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(report.diagnosticLogs, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(logColor(for: line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
            }
            .frame(height: 120)
            .background(Color(NSColor.textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .cornerRadius(6)
        }
    }

    @ViewBuilder
    private var footerView: some View {
        HStack(spacing: 10) {
            Button("Re-run") {
                Task { await runDiagnostics() }
            }
            .disabled(isLoading || isRepairing)

            if report?.canRepair == true {
                Button {
                    executeRepair()
                } label: {
                    HStack(spacing: 4) {
                        if isRepairing {
                            ProgressView().controlSize(.small)
                        }
                        Text("Repair Container")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || isRepairing)
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func statusColor(for status: VaultDiagnosticsService.VaultHealthReport.Status) -> Color {
        switch status {
        case .healthy: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func logColor(for line: String) -> Color {
        if line.contains("[ERROR]") { return .red }
        if line.contains("[WARNING]") { return .orange }
        if line.contains("[OK]") { return .green }
        return .primary
    }

    private func runDiagnostics() async {
        isLoading = true
        let rep = await VaultDiagnosticsService.shared.checkHealth(for: vaultURL)
        await MainActor.run {
            self.report = rep
            self.isLoading = false
        }
    }

    private func executeRepair() {
        isRepairing = true
        let target = vaultURL
        Task {
            do {
                let res = try await VaultDiagnosticsService.shared.repair(vaultURL: target)
                await MainActor.run {
                    self.repairResult = res
                    self.isRepairing = false
                }
                await runDiagnostics()
            } catch {
                await MainActor.run {
                    self.repairResult = "Repair failed: \(error.localizedDescription)"
                    self.isRepairing = false
                }
            }
        }
    }
}
