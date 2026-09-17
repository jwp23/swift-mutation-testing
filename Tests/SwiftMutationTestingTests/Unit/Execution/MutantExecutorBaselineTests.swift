import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("MutantExecutor baseline")
struct MutantExecutorBaselineTests {

    @Test("Given the unmutated suite fails, when execute is called, then the run aborts naming the failing tests")
    func failingBaselineAbortsTheRun() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = SPMBaselineMock(
            baselineExitCode: 1,
            baselineOutput: "Test Case '-[MyLibTests.FooTests testOne]' failed (0.002 seconds)."
        )

        await #expect(throws: BaselineError.testsFailed(tests: ["MyLibTests.FooTests.testOne"])) {
            try await makeExecutor(launcher: launcher, in: dir).execute(makeBaselineInput(in: dir))
        }

        #expect(await launcher.mutantRequests.isEmpty)
    }

    @Test("Given a suite whose duration is unknown, when the baseline runs, then it gets a mutant's longest latitude")
    func baselineIsGivenAMultipleOfTheConfiguredTimeout() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = SPMBaselineMock()

        _ = try await makeExecutor(launcher: launcher, timeout: 30, in: dir).execute(makeBaselineInput(in: dir))

        let expected = 30 * MutantTimeout.baselineCoefficient
        let timeout = try #require(await launcher.baselineRequests.first?.timeout)

        // A deadline computed from the configured timeout, not the timeout verbatim: the request
        // gets whatever remains of it once the run has started, which is a hair under `expected`.
        #expect(timeout > expected - 1 && timeout <= expected)
    }

    @Test("Given tests slower than the configured timeout, when a mutant runs them, then it is given a multiple of it")
    func mutantTimeoutScalesWithTheMeasuredBaseline() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = SPMBaselineMock(
            baselineOutput: "Test Case '-[MyLibTests.FooTests testOne]' passed (10.000 seconds)."
        )

        let results = try await makeExecutor(
            launcher: launcher, timeout: 5, testTarget: "FixtureTests/FooTests", in: dir
        )
        .execute(makeBaselineInput(in: dir))

        // What is left of the mutant's budget when its run starts, a hair under the whole of it.
        let timeout = try #require(await launcher.mutantRequests.first?.timeout)

        #expect(results.count == 1)
        #expect(timeout <= 50 && timeout > 49)
    }
}

private func makeExecutor(
    launcher: any ProcessLaunching,
    timeout: Double = 60,
    testTarget: String? = nil,
    in dir: URL
) -> MutantExecutor {
    MutantExecutor(
        configuration: makeRunnerConfiguration(
            projectPath: dir.path, projectType: .spm, testTarget: testTarget, timeout: timeout
        ),
        launcher: launcher
    )
}

private func makeBaselineInput(in dir: URL) -> RunnerInput {
    let sourceFile = dir.appendingPathComponent("Foo.swift")
    try? "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

    return makeRunnerInput(
        projectPath: dir.path,
        projectType: .spm,
        schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
        mutants: [
            makeMutantDescriptor(
                id: "m0",
                filePath: sourceFile.path,
                originalText: "true",
                mutatedText: "false",
                operatorIdentifier: "BooleanLiteralReplacement",
                replacementKind: .booleanLiteral,
                description: "true → false",
                isSchematizable: true,
                mutatedSourceContent: "let x = false"
            )
        ]
    )
}
