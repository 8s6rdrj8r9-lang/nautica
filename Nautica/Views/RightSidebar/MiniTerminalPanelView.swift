import SwiftUI
import AppKit

/// A terminal command log entry.
struct TerminalLogEntry: Identifiable {
    let id = UUID()
    let command: String
    let output: String
    let exitCode: Int32
    let timestamp: Date
}

/// Right sidebar panel embedding a lightweight, interactive shell runner anchored
/// directly to the active browsing folder.
struct MiniTerminalPanelView: View {
    let currentFolderURL: URL
    var onOpenExternalTerminal: (URL) -> Void

    @State private var commandText = ""
    @State private var logs: [TerminalLogEntry] = []
    @State private var isRunning = false
    @State private var commandHistory: [String] = []
    @State private var historyIndex: Int = -1

    private let quickCommands = ["ls -la", "pwd", "git status", "git diff", "git log -3 --oneline", "du -sh *"]

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            directoryPromptBar
            Divider()
            consoleArea
            Divider()
            quickCommandsBar
            Divider()
            commandInputBar
        }
    }

    // MARK: - Subviews

    private var headerBar: some View {
        HStack {
            Label("Terminal Console", systemImage: "terminal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Spacer()

            if !logs.isEmpty {
                Button(action: { logs.removeAll() }) {
                    Text("Clear")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear console output")
            }

            Button(action: { onOpenExternalTerminal(currentFolderURL) }) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open in external terminal emulator")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var directoryPromptBar: some View {
        HStack(spacing: 6) {
            Text("📁")
                .font(.caption2)
            Text(abbreviatedPath(currentFolderURL.path))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var consoleArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if logs.isEmpty {
                        emptyConsolePrompt
                    } else {
                        ForEach(logs) { entry in
                            logEntryRow(entry)
                        }
                    }

                    if isRunning {
                        runningIndicator
                    }
                }
                .padding(10)
            }
            .background(Color(NSColor.textBackgroundColor))
            .onChange(of: logs.count) {
                if let lastID = logs.last?.id {
                    withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyConsolePrompt: some View {
        VStack(spacing: 8) {
            Text("Nautica Embedded Console")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("Type a shell command or select a quick action below.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private func logEntryRow(_ entry: TerminalLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("$")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                Text(entry.command)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                Spacer()
                if entry.exitCode != 0 {
                    Text("exit \(entry.exitCode)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }

            if !entry.output.isEmpty {
                Text(entry.output)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(entry.exitCode == 0 ? Color.primary : Color.red.opacity(0.85))
                    .textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .id(entry.id)
    }

    private var runningIndicator: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text("Running…")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
        .id("runningIndicator")
    }

    private var quickCommandsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(quickCommands, id: \.self) { cmd in
                    Button(action: { executeCommand(cmd) }) {
                        Text(cmd)
                            .font(.system(size: 9, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(isRunning)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var commandInputBar: some View {
        HStack(spacing: 6) {
            Text("$")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.accentColor)

            TextField("Type command (e.g. ls, git status)…", text: $commandText)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .onSubmit {
                    submitCommand()
                }
                .disabled(isRunning)

            if isRunning {
                ProgressView().controlSize(.small)
            } else {
                Button(action: submitCommand) {
                    Image(systemName: "return")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .disabled(commandText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Command Execution

    private func submitCommand() {
        let cmd = commandText.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        commandText = ""
        executeCommand(cmd)
    }

    private func executeCommand(_ cmd: String) {
        isRunning = true
        commandHistory.append(cmd)
        historyIndex = commandHistory.count
        let workingDir = currentFolderURL

        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", cmd]
            process.currentDirectoryURL = workingDir

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let outStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let code = process.terminationStatus

                await MainActor.run {
                    self.logs.append(TerminalLogEntry(
                        command: cmd,
                        output: outStr,
                        exitCode: code,
                        timestamp: Date()
                    ))
                    self.isRunning = false
                }
            } catch {
                await MainActor.run {
                    self.logs.append(TerminalLogEntry(
                        command: cmd,
                        output: "Failed to execute: \(error.localizedDescription)",
                        exitCode: 1,
                        timestamp: Date()
                    ))
                    self.isRunning = false
                }
            }
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeURL.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
