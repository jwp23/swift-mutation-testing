import Testing

@testable import SwiftMutationTesting

@Suite("ScopeFilterStage")
struct ScopeFilterStageTests {
    private let stage = ScopeFilterStage()

    @Test("Given no scope, when run, then every mutation point survives")
    func unscopedRunKeepsEveryPoint() {
        let points = [makeMutationPoint(filePath: "/p/Foo.swift", line: 3)]

        #expect(stage.run(mutationPoints: points, scope: nil).count == 1)
    }

    @Test("Given a scope, when run, then only the points on its lines survive")
    func keepsOnlyPointsInScope() {
        let points = [
            makeMutationPoint(filePath: "/p/Foo.swift", line: 3),
            makeMutationPoint(filePath: "/p/Foo.swift", line: 30),
            makeMutationPoint(filePath: "/p/Bar.swift", line: 3),
        ]

        let result = stage.run(
            mutationPoints: points,
            scope: MutantScope(lineRangesByPath: ["Foo.swift": [1 ... 10]])
        )

        #expect(result.count == 1)
        #expect(result[0].filePath == "/p/Foo.swift")
        #expect(result[0].line == 3)
    }

    @Test("Given a scope covering nothing discovered, when run, then no point survives")
    func emptyScopeKeepsNothing() {
        let points = [makeMutationPoint(filePath: "/p/Foo.swift", line: 3)]

        #expect(stage.run(mutationPoints: points, scope: MutantScope(lineRangesByPath: [:])).isEmpty)
    }

    private func makeMutationPoint(filePath: String, line: Int) -> MutationPoint {
        MutationPoint(
            operatorIdentifier: "BooleanLiteralReplacement",
            filePath: filePath,
            line: line,
            column: 9,
            utf8Offset: 0,
            originalText: "true",
            mutatedText: "false",
            replacement: .booleanLiteral,
            description: "true -> false"
        )
    }
}
