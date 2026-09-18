import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("FallbackExecutor")
struct FallbackExecutorTests {
    @Test("Given SPM project type with successful build, when execute called, then results are returned")
    func spmFallbackBuildSuccessReturnsResults() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let config = makeRunnerConfiguration(projectPath: dir.path, projectType: .spm)

        let launcher = MockProcessLauncher(exitCode: 0)
        let deps = makeExecutionDeps(
            launcher: launcher,
            cacheStorePath: dir.appendingPathComponent("cache.json").path
        )

        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true
        )

        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [
                SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")
            ],
            mutants: [mutant]
        )

        let executor = FallbackExecutor(deps: deps, configuration: config)
        let results = try await executor.execute(input: input, mutants: input.mutants, pool: pool)

        #expect(results.count == 1)
    }

    @Test(
        "Given SPM project type with different timeout and buildTimeout, when fallback build called, then build is given buildTimeout, not per-mutant timeout"
    )
    func spmFallbackBuildUsesCorrectBuildTimeout() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let launcher = BuildTimeoutTrackingMock()
        let config = makeRunnerConfiguration(
            projectPath: dir.path,
            projectType: .spm,
            timeout: 10,
            buildTimeout: 800
        )
        let deps = makeExecutionDeps(
            launcher: launcher,
            cacheStorePath: dir.appendingPathComponent("cache.json").path
        )

        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true
        )

        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [
                SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")
            ],
            mutants: [mutant]
        )

        let executor = FallbackExecutor(deps: deps, configuration: config)
        _ = try await executor.execute(input: input, mutants: input.mutants, pool: pool)

        let buildTimeouts = await launcher.buildTimeouts
        #expect(!buildTimeouts.isEmpty)
        #expect(buildTimeouts.first == 800)
    }

    @Test(
        "Given Xcode project type with different timeout and buildTimeout, when fallback build called, then build is given buildTimeout, not per-mutant timeout"
    )
    func xcodeFallbackBuildUsesCorrectBuildTimeout() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let launcher = BuildTimeoutTrackingMock()
        let config = makeRunnerConfiguration(
            projectPath: dir.path,
            projectType: .xcode(scheme: "MyScheme", destination: "generic/platform=macOS"),
            timeout: 10,
            buildTimeout: 700
        )
        let deps = makeExecutionDeps(
            launcher: launcher,
            cacheStorePath: dir.appendingPathComponent("cache.json").path
        )

        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true
        )

        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .xcode(scheme: "MyScheme", destination: "generic/platform=macOS"),
            schematizedFiles: [
                SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")
            ],
            mutants: [mutant]
        )

        let executor = FallbackExecutor(deps: deps, configuration: config)
        _ = try await executor.execute(input: input, mutants: input.mutants, pool: pool)

        let buildTimeouts = await launcher.buildTimeouts
        #expect(!buildTimeouts.isEmpty)
        #expect(buildTimeouts.first == 700)
    }
}
