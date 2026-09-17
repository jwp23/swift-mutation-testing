import Foundation

/// The diff between a git reference and the working tree, read from the project's own checkout.
///
/// The diff is taken relative to the project path, so a package that lives inside a larger
/// repository is scoped by its own changes and not by every change the repository holds.
struct GitDiffReader: Sendable {
    /// How long the diff may take before the run gives up on it. A diff against a reference the
    /// checkout already has is near-instant; anything slower is a repository problem, not a wait.
    static let timeout: Double = 30

    let launcher: any ProcessLaunching

    func diff(since ref: String, projectPath: String) async throws -> String {
        let request = ProcessRequest(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["diff", "-U0", "--relative", ref],
            environment: nil,
            additionalEnvironment: [:],
            workingDirectoryURL: URL(fileURLWithPath: projectPath, isDirectory: true),
            timeout: Self.timeout
        )

        guard let result = try? await launcher.launchCapturing(request) else {
            throw failure(ref: ref, projectPath: projectPath)
        }

        guard result.exitCode == 0 else {
            throw failure(ref: ref, projectPath: projectPath)
        }

        return result.output
    }

    private func failure(ref: String, projectPath: String) -> UsageError {
        UsageError(message: "--since '\(ref)': could not read a git diff in '\(projectPath)'")
    }
}
