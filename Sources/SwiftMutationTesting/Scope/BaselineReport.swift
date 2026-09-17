import Foundation

/// A mutation report from an earlier full run, which a scoped run reads to find the mutants a
/// changed test file used to kill.
///
/// Those mutants go back in scope wherever they live. A test kills mutants in files the naming
/// convention never pairs it with, and a change that weakens it would otherwise be judged by the
/// lines of the test itself — which carry no mutants at all.
struct BaselineReport: Sendable {
    init(path: String) throws {
        guard
            let data = FileManager.default.contents(atPath: path),
            let payload = try? JSONDecoder().decode(MutationReportPayload.self, from: data)
        else {
            throw UsageError(message: "--baseline-report: could not read a mutation report from '\(path)'")
        }

        self.payload = payload
    }

    private let payload: MutationReportPayload

    /// Scope covering every mutant the report records as killed by a test that one of
    /// `changedTestFilePaths` declares.
    func scope(killedByTestsIn changedTestFilePaths: [String]) -> MutantScope {
        guard !changedTestFilePaths.isEmpty else { return MutantScope(lineRangesByPath: [:]) }

        let changedKillers = testsDeclaredIn(changedTestFilePaths)
        var lineRangesByPath: [String: [ClosedRange<Int>]] = [:]

        for (reportPath, file) in payload.files {
            let lines =
                file.mutants
                .filter { $0.killedBy.map(changedKillers.contains) ?? false }
                .map { $0.location.start.line ... $0.location.start.line }

            guard !lines.isEmpty else { continue }

            lineRangesByPath[projectRelativePath(reportPath), default: []] += lines
        }

        return MutantScope(lineRangesByPath: lineRangesByPath)
    }

    /// Of the tests the report names as killers, those a changed test file declares. Each name is
    /// traced back to its file once, however many mutants it killed.
    private func testsDeclaredIn(_ testFilePaths: [String]) -> Set<String> {
        let resolver = KillerTestFileResolver(testFilePaths: testFilePaths)
        let killers = Set(payload.files.values.flatMap { $0.mutants.compactMap(\.killedBy) })

        return killers.filter { resolver.resolve(testName: $0) != nil }
    }

    /// The path a report keys a file by, which a reporter writes with the project root stripped and
    /// so with a leading separator that a scope path must not carry.
    private func projectRelativePath(_ reportPath: String) -> String {
        String(reportPath.drop(while: { $0 == "/" }))
    }
}
