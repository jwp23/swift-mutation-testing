import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SPMProcessLauncher")
struct SPMProcessLauncherTests {
    private let launcher = SPMProcessLauncher()

    @Test("Given a successful executable, when launched, then returns zero exit code")
    func launchReturnsSuccessExitCode() async throws {
        let exitCode = try await launcher.launch(
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            arguments: [],
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: 10
        )

        #expect(exitCode == 0)
    }

    @Test("Given a failing executable, when launched, then returns non-zero exit code")
    func launchReturnsFailureExitCode() async throws {
        let exitCode = try await launcher.launch(
            executableURL: URL(fileURLWithPath: "/usr/bin/false"),
            arguments: [],
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: 10
        )

        #expect(exitCode != 0)
    }

    @Test("Given echo command, when launched capturing, then output contains the argument")
    func launchCapturingReturnsStdout() async throws {
        let result = try await launcher.launchCapturing(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/bin/echo"),
                arguments: ["hello world"],
                environment: nil,
                additionalEnvironment: [:],
                workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                timeout: 10
            )
        )

        #expect(result.exitCode == 0)
        #expect(result.output.contains("hello world"))
    }

    @Test("Given environment variables, when launched capturing, then process receives the variables")
    func launchCapturingPassesEnvironment() async throws {
        let result = try await launcher.launchCapturing(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "echo $TEST_VAR"],
                environment: ["TEST_VAR": "expected_value"],
                additionalEnvironment: [:],
                workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                timeout: 10
            )
        )

        #expect(result.exitCode == 0)
        #expect(result.output.contains("expected_value"))
    }

    @Test("Given stderr output, when launched capturing, then stderr is included in output")
    func launchCapturingCapturesStderr() async throws {
        let result = try await launcher.launchCapturing(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "echo error_text >&2"],
                environment: nil,
                additionalEnvironment: [:],
                workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                timeout: 10
            )
        )

        #expect(result.output.contains("error_text"))
    }

    @Test("Given long-running process and short timeout, when timeout expires, then returns minus one exit code")
    func launchTimesOutAndReturnsMinus1() async throws {
        let exitCode = try await launcher.launch(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["60"],
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: 0.5
        )

        #expect(exitCode == -1)
    }

    @Test("Given non-existent executable, when launched, then throws")
    func launchThrowsForNonExistentExecutable() async {
        await #expect(throws: (any Error).self) {
            try await launcher.launch(
                executableURL: URL(fileURLWithPath: "/nonexistent/binary"),
                arguments: [],
                workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                timeout: 10
            )
        }
    }

    @Test("Given non-existent executable, when launchCapturing called, then throws")
    func launchCapturingThrowsForNonExistentExecutable() async {
        await #expect(throws: (any Error).self) {
            try await launcher.launchCapturing(
                ProcessRequest(
                    executableURL: URL(fileURLWithPath: "/nonexistent/binary"),
                    arguments: [],
                    environment: nil,
                    additionalEnvironment: [:],
                    workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                    timeout: 10
                )
            )
        }
    }

    @Test("Given long-running process and short timeout, when launchCapturing times out, then returns minus one")
    func launchCapturingTimesOut() async throws {
        let result = try await launcher.launchCapturing(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["60"],
                environment: nil,
                additionalEnvironment: [:],
                workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                timeout: 0.5
            )
        )

        #expect(result.exitCode == -1)
    }

    @Test("Given task is cancelled while launch running, when cancelled, then process is terminated")
    func cancelledLaunchTerminatesProcess() async throws {
        let task = Task {
            try await launcher.launch(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["60"],
                workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                timeout: 60
            )
        }

        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        let exitCode = try await task.value
        #expect(exitCode == -1)
    }

    @Test("Given additionalEnvironment, when launched capturing, then process receives merged variable")
    func launchCapturingMergesAdditionalEnvironment() async throws {
        let result = try await launcher.launchCapturing(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "echo $EXTRA_VAR"],
                environment: nil,
                additionalEnvironment: ["EXTRA_VAR": "merged_value"],
                workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                timeout: 10
            )
        )

        #expect(result.exitCode == 0)
        #expect(result.output.contains("merged_value"))
    }

    @Test("Given task is cancelled while launchCapturing running, when cancelled, then process is terminated")
    func cancelledLaunchCapturingTerminatesProcess() async throws {
        let task = Task {
            try await launcher.launchCapturing(
                ProcessRequest(
                    executableURL: URL(fileURLWithPath: "/bin/sleep"),
                    arguments: ["60"],
                    environment: nil,
                    additionalEnvironment: [:],
                    workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                    timeout: 60
                )
            )
        }

        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        let result = try await task.value
        #expect(result.exitCode == -1)
    }

    @Test(
        "Given a process printing a matching line, when launched streaming, then it is stopped there instead of running on"
    )
    func launchStreamingStopsAtTheMatchingLine() async throws {
        let start = Date()
        let result = try await launcher.launchStreaming(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "echo first; echo stop-here; sleep 20; echo never"],
                environment: nil,
                additionalEnvironment: [:],
                workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                timeout: 60
            ),
            stopWhen: { $0.contains("stop-here") }
        )

        #expect(result.stoppedEarly)
        #expect(result.output.contains("first"))
        #expect(result.output.contains("stop-here"))
        #expect(!result.output.contains("never"))
        #expect(result.exitCode != 0)
        #expect(Date().timeIntervalSince(start) < 10)
    }

    @Test("Given a process printing no matching line, when launched streaming, then it runs to completion")
    func launchStreamingRunsToCompletionWithoutAMatch() async throws {
        let result = try await launcher.launchStreaming(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "echo to stdout; echo to stderr 1>&2; exit 3"],
                environment: nil,
                additionalEnvironment: [:],
                workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                timeout: 10
            ),
            stopWhen: { _ in false }
        )

        #expect(!result.stoppedEarly)
        #expect(result.exitCode == 3)
        #expect(result.output.contains("to stdout"))
        #expect(result.output.contains("to stderr"))
    }

    @Test("Given a long-running process and short timeout, when launched streaming, then returns minus one")
    func launchStreamingTimesOut() async throws {
        let result = try await launcher.launchStreaming(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["60"],
                environment: nil,
                additionalEnvironment: [:],
                workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                timeout: 0.5
            ),
            stopWhen: { _ in false }
        )

        #expect(result.exitCode == -1)
        #expect(!result.stoppedEarly)
    }

    @Test("Given task is cancelled while launchStreaming running, when cancelled, then process is terminated")
    func cancelledLaunchStreamingTerminatesProcess() async throws {
        let task = Task {
            try await launcher.launchStreaming(
                ProcessRequest(
                    executableURL: URL(fileURLWithPath: "/bin/sleep"),
                    arguments: ["60"],
                    environment: nil,
                    additionalEnvironment: [:],
                    workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                    timeout: 60
                ),
                stopWhen: { _ in false }
            )
        }

        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        let result = try await task.value
        #expect(result.exitCode == -1)
    }

    /// A descendant that calls `setsid()` leaves the launched process's group, so nothing the
    /// timeout signals reaches it once the root has exited and been reaped — the parent-pid walk
    /// `killProcessTree` depends on can no longer find it either. It keeps the pipe's write end
    /// open, so the read never reaches end of file. The launch has to come back anyway.
    @Test(
        "Given an escaped descendant holding the output open, when the process exits, then the launch still returns what it read"
    )
    func launchStreamingReturnsWhenAnEscapedDescendantHoldsTheOutputOpen() async throws {
        let pidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("escaped-\(UUID().uuidString).pid")
        defer { killEscapedDescendant(recordedIn: pidFile) }

        let escapee =
            "perl -e 'use POSIX; POSIX::setsid(); open(F, \">\", $ARGV[0]); print F $$; close F; sleep 600;'"
        let start = Date()
        let result = try await launcher.launchStreaming(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "\(escapee) \(pidFile.path) & echo parent-line; \(waitForEscape(pidFile))"],
                environment: nil,
                additionalEnvironment: [:],
                workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                timeout: 600
            ),
            stopWhen: { _ in false }
        )

        #expect(result.output.contains("parent-line"))
        #expect(result.exitCode == 0)
        #expect(!result.stoppedEarly)
        #expect(Date().timeIntervalSince(start) < 30)
    }
}

/// Holds the parent open until the descendant has recorded its pid — which it does only after
/// `setsid()`, so the parent cannot exit while the descendant is still inside its process group and
/// reachable by the group `SIGKILL` that follows termination. Bounded, so a descendant that never
/// starts cannot hang the parent instead.
private func waitForEscape(_ pidFile: URL) -> String {
    "i=0; while [ ! -s \(pidFile.path) ] && [ $i -lt 200 ]; do sleep 0.05; i=$((i+1)); done; [ -s \(pidFile.path) ]"
}

/// Kills the escaped descendant the test left behind, and the session it made itself the leader of.
private func killEscapedDescendant(recordedIn pidFile: URL) {
    defer { try? FileManager.default.removeItem(at: pidFile) }

    guard
        let contents = try? String(contentsOf: pidFile, encoding: .utf8),
        let pid = Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines))
    else { return }

    kill(-pid, SIGKILL)
    kill(pid, SIGKILL)
}
