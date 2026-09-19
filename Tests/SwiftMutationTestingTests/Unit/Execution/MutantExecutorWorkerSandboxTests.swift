import Foundation
import Testing

@testable import SwiftMutationTesting

extension SandboxRootHookGlobalStateTests {
    @Suite("MutantExecutor worker sandboxes")
    struct MutantExecutorWorkerSandboxTests {

        @Test(
            "Given fewer mutants than workers, when the run is prepared, then it replicates no sandbox a mutant cannot use"
        )
        func sandboxReplicationIsLimitedByTheMutantCount() async throws {
            let dir = try FileHelpers.makeTemporaryDirectory()
            defer { FileHelpers.cleanup(dir) }

            let roots = SandboxRootCounter()
            sandboxRootCreatedHook = { roots.increment() }
            defer { sandboxRootCreatedHook = nil }

            let executor = MutantExecutor(
                configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm, concurrency: 8),
                launcher: SPMBaselineMock()
            )

            let results = try await executor.execute(makeTwoMutantInput(in: dir))

            // The sandbox that was built plus one replica: two mutants can occupy two sandboxes, and
            // the other six workers have nothing to run in a copy of the build directory.
            #expect(results.count == 2)
            #expect(roots.count == 2)
        }
    }
}

/// Counts the sandbox roots a run creates, from the hook `SandboxFactory` calls as it makes each
/// one. Sandbox creation and replication can be reached from more than one task, so the count is
/// taken under a lock.
private final class SandboxRootCounter: @unchecked Sendable {

    var count: Int {
        lock.withLock { created }
    }

    func increment() {
        lock.withLock { created += 1 }
    }

    private let lock = NSLock()
    private var created = 0
}

private func makeTwoMutantInput(in dir: URL) -> RunnerInput {
    let sourceFile = dir.appendingPathComponent("Foo.swift")
    try? "let x = true\nlet y = true".write(to: sourceFile, atomically: true, encoding: .utf8)

    let mutants = ["m0", "m1"].map { id in
        makeMutantDescriptor(
            id: id,
            filePath: sourceFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let x = false"
        )
    }

    return makeRunnerInput(
        projectPath: dir.path,
        projectType: .spm,
        concurrency: 8,
        schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
        mutants: mutants
    )
}
