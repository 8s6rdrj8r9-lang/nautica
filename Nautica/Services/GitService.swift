import Foundation
import AppKit

/// Comprehensive Git version control service for repository discovery, status resolution,
/// branch management, staging, committing, and diff generation.
public final class GitService: Sendable {
    public static let shared = GitService()

    private init() {}

    // MARK: - Process Execution

    /// Runs a git command in the specified directory and returns standard output.
    @discardableResult
    public func runGit(_ args: [String], at directory: URL) -> (output: String, error: String, exitCode: Int32) {
        let isDir = (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let effectiveDir = isDir ? directory : directory.deletingLastPathComponent()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = effectiveDir

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let outStr = String(data: outData, encoding: .utf8) ?? ""
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            return (outStr, errStr, process.terminationStatus)
        } catch {
            return ("", error.localizedDescription, -1)
        }
    }

    /// Runs a git command in the specified directory and returns raw standard output data.
    @discardableResult
    public func runGitData(_ args: [String], at directory: URL) -> (output: Data, error: String, exitCode: Int32) {
        let isDir = (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let effectiveDir = isDir ? directory : directory.deletingLastPathComponent()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = effectiveDir

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let errStr = String(data: errData, encoding: .utf8) ?? ""
            return (outData, errStr, process.terminationStatus)
        } catch {
            return (Data(), error.localizedDescription, -1)
        }
    }

    // MARK: - Repository Discovery & Root Resolution

    /// Returns whether the given directory resides inside a Git working tree.
    public func isGitRepository(at directory: URL) -> Bool {
        guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return false }
        let result = runGit(["rev-parse", "--is-inside-work-tree"], at: directory)
        return result.exitCode == 0 && result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    /// Resolves the root directory URL of the enclosing Git repository, or nil if not tracked.
    public func repoRoot(at directory: URL) -> URL? {
        guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return nil }
        let result = runGit(["rev-parse", "--show-toplevel"], at: directory)
        guard result.exitCode == 0 else { return nil }
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    // MARK: - Branch Operations

    /// Returns the current active branch name, or "HEAD" if detached.
    public func currentBranch(at directory: URL) -> String? {
        guard isGitRepository(at: directory) else { return nil }
        let result = runGit(["branch", "--show-current"], at: directory)
        let branch = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if branch.isEmpty {
            // Detached HEAD or initial commit: check rev-parse --short HEAD
            let head = runGit(["rev-parse", "--short", "HEAD"], at: directory).output.trimmingCharacters(in: .whitespacesAndNewlines)
            return head.isEmpty ? "HEAD" : "HEAD (\(head))"
        }
        return branch
    }

    /// Returns all local branch names in the repository.
    public func localBranches(at directory: URL) -> [String] {
        guard isGitRepository(at: directory) else { return [] }
        let result = runGit(["branch", "--format=%(refname:short)"], at: directory)
        guard result.exitCode == 0 else { return [] }
        return result.output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Switches (checkouts) to an existing local branch.
    public func switchBranch(to branchName: String, at directory: URL) async throws {
        let result = runGit(["checkout", branchName], at: directory)
        if result.exitCode != 0 {
            throw NSError(
                domain: "GitService",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: result.error.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
        }
    }

    /// Creates a new branch from current HEAD and switches to it.
    public func createBranch(named newBranchName: String, at directory: URL) async throws {
        let result = runGit(["checkout", "-b", newBranchName], at: directory)
        if result.exitCode != 0 {
            throw NSError(
                domain: "GitService",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: result.error.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
        }
    }

    /// Unquotes and unescapes C-style quoted paths emitted by Git porcelain format.
    public func unquotePorcelainPath(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count >= 2 else {
            return trimmed
        }
        let inner = String(trimmed.dropFirst().dropLast())
        var bytes: [UInt8] = []
        let chars = Array(inner)
        var i = 0
        while i < chars.count {
            if chars[i] == "\\" && i + 1 < chars.count {
                let next = chars[i + 1]
                if next == "\\" { bytes.append(UInt8(ascii: "\\")); i += 2; continue }
                if next == "\"" { bytes.append(UInt8(ascii: "\"")); i += 2; continue }
                if next == "t" { bytes.append(UInt8(ascii: "\t")); i += 2; continue }
                if next == "n" { bytes.append(UInt8(ascii: "\n")); i += 2; continue }
                if next == "r" { bytes.append(UInt8(ascii: "\r")); i += 2; continue }
                if next >= "0" && next <= "7" {
                    var octalStr = ""
                    var j = i + 1
                    while j < min(i + 4, chars.count) && chars[j] >= "0" && chars[j] <= "7" {
                        octalStr.append(chars[j])
                        j += 1
                    }
                    if let byteVal = UInt8(octalStr, radix: 8) {
                        bytes.append(byteVal)
                        i = j
                        continue
                    }
                }
                bytes.append(next.asciiValue ?? 0)
                i += 2
            } else {
                if let ascii = chars[i].asciiValue {
                    bytes.append(ascii)
                } else {
                    bytes.append(contentsOf: String(chars[i]).utf8)
                }
                i += 1
            }
        }
        return String(data: Data(bytes), encoding: .utf8) ?? inner
    }

    // MARK: - Status Resolution & File Mapping

    /// Returns a map of relative file paths and full file paths to their `GitFileState`.
    /// Runs `git status --porcelain=v1 -z -uall` to reliably parse paths with spaces,
    /// quotes, and Unicode characters without escaping issues, and keys strictly by exact repository paths.
    public func statusMap(forDirectory directory: URL) -> [String: GitFileState] {
        guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
              isGitRepository(at: directory),
              let root = repoRoot(at: directory) else {
            return [:]
        }

        let rootPath = root.standardizedFileURL.path
        let dirPath = directory.standardizedFileURL.path
        var args = ["status", "--porcelain=v1", "-z"]
        if dirPath != rootPath && dirPath.hasPrefix(rootPath) {
            let relativeDir = String(dirPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !relativeDir.isEmpty {
                args.append(relativeDir)
            }
        }

        let result = runGitData(args, at: root)
        guard result.exitCode == 0 else { return [:] }

        var map: [String: GitFileState] = [:]
        let data = result.output

        var index = data.startIndex
        while index < data.endIndex {
            guard let nulIndex = data[index...].firstIndex(of: 0) else { break }
            let entryData = data[index..<nulIndex]
            index = nulIndex + 1

            guard entryData.count >= 3 else { continue }
            let indexStatus = Character(UnicodeScalar(entryData[entryData.startIndex]))
            let workTreeStatus = Character(UnicodeScalar(entryData[entryData.index(after: entryData.startIndex)]))
            let pathData = entryData.dropFirst(3)
            guard let rawPath = String(data: Data(pathData), encoding: .utf8) else { continue }

            let finalPath = rawPath
            // If rename or copy (R or C), skip the following original-path field
            if indexStatus == "R" || indexStatus == "C" || workTreeStatus == "R" || workTreeStatus == "C" {
                if let nextNul = data[index...].firstIndex(of: 0) {
                    index = nextNul + 1
                }
            }

            let state: GitFileState
            if indexStatus == "?" && workTreeStatus == "?" {
                state = .untracked
            } else if indexStatus == "U" || workTreeStatus == "U" {
                state = .conflict
            } else if indexStatus == "A" || workTreeStatus == "A" {
                state = .added
            } else if indexStatus == "D" || workTreeStatus == "D" {
                state = .deleted
            } else if indexStatus == "R" || workTreeStatus == "R" {
                state = .renamed
            } else if indexStatus == "M" || workTreeStatus == "M" {
                state = .modified
            } else {
                state = .modified
            }

            map[finalPath] = state
            let fullPath = rootPath + "/" + finalPath
            map[fullPath] = state
        }

        return map
    }

    /// Checks whether the working tree contains uncommitted modifications.
    public func isDirty(at directory: URL) -> Bool {
        guard isGitRepository(at: directory) else { return false }
        let result = runGit(["status", "--porcelain"], at: directory)
        return !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Staging & Committing

    /// Stages the given file URLs (`git add`).
    public func stage(urls: [URL], at directory: URL) async throws {
        guard !urls.isEmpty else { return }
        var args = ["add", "--"]
        args.append(contentsOf: urls.map(\.path))
        let result = runGit(args, at: directory)
        if result.exitCode != 0 {
            throw NSError(
                domain: "GitService",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: result.error.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
        }
    }

    /// Unstages the given file URLs (`git restore --staged`).
    public func unstage(urls: [URL], at directory: URL) async throws {
        guard !urls.isEmpty else { return }
        var args = ["restore", "--staged", "--"]
        args.append(contentsOf: urls.map(\.path))
        let result = runGit(args, at: directory)
        if result.exitCode != 0 {
            // Fallback for older git versions
            var resetArgs = ["reset", "HEAD", "--"]
            resetArgs.append(contentsOf: urls.map(\.path))
            _ = runGit(resetArgs, at: directory)
        }
    }

    /// Discards working tree changes for the given URLs (`git checkout --` or `git restore`).
    public func discardChanges(for urls: [URL], at directory: URL) async throws {
        guard !urls.isEmpty else { return }
        var args = ["restore", "--"]
        args.append(contentsOf: urls.map(\.path))
        let result = runGit(args, at: directory)
        if result.exitCode != 0 {
            var fallbackArgs = ["checkout", "--"]
            fallbackArgs.append(contentsOf: urls.map(\.path))
            _ = runGit(fallbackArgs, at: directory)
        }
    }

    /// Discards working tree changes for a single URL.
    public func discardChanges(for url: URL, at directory: URL) async throws {
        try await discardChanges(for: [url], at: directory)
    }

    /// Creates a commit with the specified message.
    public func commit(message: String, at directory: URL) async throws {
        let result = runGit(["commit", "-m", message], at: directory)
        if result.exitCode != 0 {
            throw NSError(
                domain: "GitService",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: result.error.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
        }
    }

    // MARK: - Diff Generation

    /// Computes the unified diff for a single file URL or the entire directory.
    public func diff(for fileURL: URL? = nil, at directory: URL) async throws -> String {
        guard isGitRepository(at: directory) else { return "" }
        var args = ["diff", "HEAD"]
        if let fileURL {
            args.append("--")
            args.append(fileURL.path)
        }
        let result = runGit(args, at: directory)
        if result.output.isEmpty, let fileURL {
            // Check unstaged diff against index
            let unstagedResult = runGit(["diff", "--", fileURL.path], at: directory)
            if !unstagedResult.output.isEmpty {
                return unstagedResult.output
            }
            // Check staged diff
            let stagedResult = runGit(["diff", "--cached", "--", fileURL.path], at: directory)
            return stagedResult.output
        }
        return result.output
    }
}
