import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("ProcessRunner cancellation race")
struct ProcessRunnerTests {
    /// Records terminated pids from `postTerminationCleanup`, which Foundation invokes from
    /// arbitrary queues — the same concurrent access this suite exercises.
    private final class TerminatedPIDs: @unchecked Sendable {
        private let lock = NSLock()
        private var pids: [Int32] = []

        func record(_ pid: Int32) {
            lock.lock()
            pids.append(pid)
            lock.unlock()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return pids.count
        }
    }

    /// Holds a task suspended until released, so a caller can cancel it before its body ever
    /// runs. `withTaskCancellationHandler` runs `onCancel` synchronously to completion before
    /// `operation` when the task is already cancelled at the point it's entered — cancelling a
    /// task while it's parked here, then releasing it, therefore forces that ordering
    /// deterministically instead of leaving it to scheduler timing.
    private actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func open() {
            isOpen = true
            waiters.forEach { $0.resume() }
            waiters.removeAll()
        }

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    /// Each of `ProcessRunner`'s three launch paths follows the same run-then-race-onCancel
    /// shape; parameterizing over them exercises all three rather than only `launch`.
    private enum LaunchKind: String, CaseIterable, Sendable, CustomStringConvertible {
        case launch, launchCapturing, launchStreaming

        var description: String { rawValue }

        private static let request = ProcessRequest(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["2"],
            environment: nil,
            additionalEnvironment: [:],
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: 30
        )

        func perform(with runner: ProcessRunner) async {
            switch self {
            case .launch:
                _ = try? await runner.launch(
                    executableURL: URL(fileURLWithPath: "/bin/sleep"),
                    arguments: ["2"],
                    workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                    timeout: 30
                )
            case .launchCapturing:
                _ = try? await runner.launchCapturing(Self.request)
            case .launchStreaming:
                _ = try? await runner.launchStreaming(Self.request) { _ in false }
            }
        }
    }

    @Test(
        "Given a task already cancelled before it starts, when many such launches run concurrently, then every process is still killed",
        .timeLimit(.minutes(1)),
        arguments: LaunchKind.allCases
    )
    private func cancellationRacingProcessRunStillKillsEveryProcess(kind: LaunchKind) async throws {
        let iterations = 30
        let terminated = TerminatedPIDs()

        let runner = ProcessRunner(
            postTerminationCleanup: { pid in terminated.record(pid) },
            killProcessTree: { pid in
                guard pid > 0 else { return }
                kill(-pid, SIGKILL)
            }
        )

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< iterations {
                group.addTask {
                    let gate = Gate()
                    let task = Task {
                        await gate.wait()
                        await kind.perform(with: runner)
                    }
                    // Cancels while the task is still parked on the gate, guaranteeing it is
                    // already cancelled by the time it reaches process.run() once released.
                    task.cancel()
                    await gate.open()
                }
            }
        }

        // A process actually killed reports back in milliseconds; one that escaped the race
        // keeps running for its full 2-second sleep, well past this window.
        let deadline = Date().addingTimeInterval(1.5)
        while terminated.count < iterations, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(
            terminated.count == iterations,
            "\(iterations - terminated.count) of \(iterations) cancelled \(kind) launches escaped the cancellation race and were left running"
        )
    }
}
