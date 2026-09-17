import Foundation

/// Why the unmutated suite could not serve as a baseline, and the run was abandoned before any
/// mutant ran.
///
/// Nothing a mutant does can be believed once the suite fails without it: every mutant would be
/// reported killed by a failure that was already there, and the mutation score would be a
/// flattering fiction. The run stops instead, naming what to fix.
enum BaselineError: Error, Equatable, LocalizedError {
    case testsFailed(tests: [String])
    case didNotFinish(seconds: Double)
    case runFailed(output: String)

    var errorDescription: String? {
        switch self {
        case .testsFailed(let tests):
            return
                "The test suite fails before any mutation is applied, so every mutant would be reported "
                + "killed by a failure that is already there. Fix these tests first:\n"
                + tests.map { "  - \($0)" }.joined(separator: "\n")

        case .didNotFinish(let seconds):
            return
                "The unmutated test suite did not finish within \(formatted(seconds)) seconds, so no "
                + "mutant's timeout can be measured against it. Raise --timeout past the time the suite needs."

        case .runFailed(let output):
            var message = "The unmutated test suite could not be run, so no mutant's result would mean anything."
            if !output.isEmpty { message = output + "\n" + message }
            return message
        }
    }

    private func formatted(_ seconds: Double) -> String {
        String(format: "%g", seconds)
    }
}
