import Foundation

@testable import SwiftMutationTesting

/// Test double for a clone step where one worker's `simctl clone` fails and every other worker's
/// succeeds. Worker index 1 fails at once; workers after it succeed only after a short delay, so
/// their simulators come into existence while the sibling failure is already propagating — the
/// clones easiest for a pool to lose track of. A cancelled delay still yields a created clone,
/// the way a real `simctl clone` leaves a simulator behind once it has made one.
///
/// Each clone reports the UDID `CLONE-<worker index>`. Every call made through the launcher is
/// recorded so tests can assert on teardown side effects (e.g. `simctl delete` per clone).
actor PartialCloneFailureLauncher: ProcessLaunching {
    init(listJSON: String = "{}") {
        self.listJSON = listJSON
    }

    private static let failingWorkerIndex = 1

    private let listJSON: String
    private(set) var recordedArguments: [[String]] = []

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        recordedArguments.append(arguments)
        return 0
    }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        recordedArguments.append(request.arguments)

        if request.arguments.contains("clone") {
            return await cloneResult(forWorkerNamed: request.arguments.last ?? "")
        }

        if request.executableURL.lastPathComponent == "xcodebuild" {
            return (1, "")
        }

        return (0, listJSON)
    }

    private func cloneResult(forWorkerNamed name: String) async -> (exitCode: Int32, output: String) {
        let index = Int(name.components(separatedBy: "-").last ?? "") ?? 0

        guard index != Self.failingWorkerIndex else { return (1, "") }

        if index > Self.failingWorkerIndex {
            try? await Task.sleep(for: .milliseconds(30))
        }

        return (0, "CLONE-\(index)\n")
    }
}
