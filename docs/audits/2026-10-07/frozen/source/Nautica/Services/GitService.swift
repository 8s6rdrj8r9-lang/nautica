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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory

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

    // MARK: - Repository Discovery & Root Resolution

    /// Returns whether the given directory resides inside a Git working tree.
    public func isGitRepository(at directory: URL) -> Bool {
        let result = runGit(["rev-parse", "--is-inside-work-tree"], at: directory)
        return result.exitCode == 0 && result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    /// Resolves the root directory URL of the enclosing Git repository, or nil if not tracked.
    public func repoRoot(at directory: URL) -> URL? {
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

    // MARK: - Status Resolution & File Mapping

    /// Returns a map of relative file paths and full file paths to their `GitFileState`.
    /// Runs `git status --porcelain` once to ensure high-performance O(1) status lookup.
    public func statusMap(forDirectory directory: URL) -> [String: GitFileState] {
        guard isGitRepository(at: directory), let root = repoRoot(at: directory) else {
            return [:]
        }

        let result = runGit(["status", "--porcelain", "-uall"], at: root)
        guard result.exitCode == 0 else { return [:] }

        var map: [String: GitFileState] = [:]
        let rootPath = root.standardizedFileURL.path

        for line in result.output.components(separatedBy: .newlines) where line.count >= 3 {
            let indexStatus = line[line.startIndex]
            let workTreeStatus = line[line.index(after: line.startIndex)]
            let rawPath = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            guard !rawPath.isEmpty else { continue }

            // Handle rename lines: "old -> new"
            let filePath: String
            if rawPath.contains(" -> ") {
                filePath = rawPath.components(separatedBy: " -> ").last ?? rawPath
            } else {
                filePath = rawPath
            }

            // Determine status
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

            // Store by repo-relative path
            map[filePath] = state

            // Also store by absolute path for instant lookup
            let fullPath = (rootPath as NSString).appendingPathComponent(filePath)
            map[fullPath] = state
            // Also store by filename for directory-relative lookups
            let filename = (filePath as NSString).lastPathComponent
            if map[filename] == nil {
                map[filename] = state
            }
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
