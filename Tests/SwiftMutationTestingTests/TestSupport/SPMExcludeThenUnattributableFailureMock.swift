import Foundation

@testable import SwiftMutationTesting

/// A schema build that narrows once and then fails on something no mutant can be blamed for: the
/// first build blames `Foo.swift`, so its mutants are excluded, and the rebuild fails with an
/// error naming no source file at all, leaving the run with no schema artifact. Every build after
/// that — the per-file fallback builds and the excluded mutants' own builds — succeeds.
actor SPMExcludeThenUnattributableFailureMock: ProcessLaunching {
    private var buildCallCount = 0

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 { 0 }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        writeMockedTestBundle(for: request)

        guard request.arguments.first == "build" else { return (0, "") }
        buildCallCount += 1

        if buildCallCount == 1 {
            let fooPath = request.workingDirectoryURL.appendingPathComponent("Foo.swift").path
            let canonical = fooPath.withCString { ptr in
                guard let resolved = realpath(ptr, nil) else { return fooPath }
                defer { free(resolved) }
                return String(cString: resolved)
            }
            return (1, "\(canonical):1:5: error: cannot convert value")
        }

        if buildCallCount == 2 {
            return (1, "error: build failed")
        }

        return (0, "")
    }
}
