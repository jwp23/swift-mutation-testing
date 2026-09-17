import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("GitDiffReader")
struct GitDiffReaderTests {
    @Test("Given git succeeds, when reading the diff, then its output is returned")
    func returnsGitOutput() async throws {
        let launcher = MockProcessLauncher(exitCode: 0, output: "@@ -1 +1 @@", producesTestBundle: false)

        let diff = try await GitDiffReader(launcher: launcher).diff(since: "main", projectPath: "/p")

        #expect(diff == "@@ -1 +1 @@")
    }

    @Test("Given a reference git cannot resolve, when reading the diff, then it throws a usage error")
    func failingGitThrowsUsageError() async {
        let launcher = MockProcessLauncher(exitCode: 128, output: "fatal: bad revision", producesTestBundle: false)

        await #expect(throws: UsageError.self) {
            _ = try await GitDiffReader(launcher: launcher).diff(since: "nope", projectPath: "/p")
        }
    }

    @Test("Given git cannot be launched, when reading the diff, then it throws a usage error")
    func unlaunchableGitThrowsUsageError() async {
        let launcher = MockProcessLauncher(exitCode: 0, throwsOnCapture: true, producesTestBundle: false)

        await #expect(throws: UsageError.self) {
            _ = try await GitDiffReader(launcher: launcher).diff(since: "main", projectPath: "/p")
        }
    }

    @Test("Given a reference, when reading the diff, then git is asked for a zero-context relative diff")
    func asksGitForZeroContextRelativeDiff() async throws {
        let launcher = RecordingProcessLauncher()

        _ = try? await GitDiffReader(launcher: launcher).diff(since: "origin/main", projectPath: "/p")

        let request = await launcher.requests.first
        #expect(request?.executableURL.lastPathComponent == "git")
        #expect(request?.arguments == ["diff", "-U0", "--relative", "origin/main"])
        #expect(request?.workingDirectoryURL.path == "/p")
    }
}
