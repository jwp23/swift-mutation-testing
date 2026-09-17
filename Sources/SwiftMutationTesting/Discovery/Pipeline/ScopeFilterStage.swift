/// Drops the mutants outside the run's scope, so that a scoped run schematizes, builds and tests
/// only the lines it was asked about. An unscoped run keeps every mutant discovery found.
struct ScopeFilterStage: Sendable {
    func run(mutationPoints: [MutationPoint], scope: MutantScope?) -> [MutationPoint] {
        guard let scope else { return mutationPoints }

        return mutationPoints.filter { scope.contains(filePath: $0.filePath, line: $0.line) }
    }
}
