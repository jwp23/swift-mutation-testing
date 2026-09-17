/// How long a mutant's tests may run before the run is called a timeout.
///
/// One fixed value is wrong in both directions: a suite slower than it times out honest survivors,
/// and a suite far faster than it makes every hung mutant wait out the whole value. The measured
/// baseline replaces the guess — a run is given a multiple of what the very tests it runs took
/// unmutated.
///
/// The configured `--timeout` stays as the floor under that, never a ceiling over it. A mutation
/// can legitimately slow code down by far more than any multiple of a millisecond-fast suite —
/// a loop that runs longer, a cache that stops hitting — and a run cut short that way is reported
/// as a timeout, which counts as caught. Under-waiting therefore inflates the score, so the
/// measured value may only ever lengthen the wait the user configured, never shorten it.
struct MutantTimeout: Sendable {
    /// Multiple of the baseline a run is allowed. Generous on purpose: mutants run concurrently,
    /// several workers to a machine, where the baseline had the machine to itself, and a run that
    /// is merely contended must not be mistaken for one that hangs.
    static let baselineCoefficient: Double = 5

    /// What the unmutated suite measured, or `nil` where no baseline was run — Xcode builds select
    /// their tests through an xctestrun plist rather than running bundles, and measure none.
    let baseline: BaselineMeasurement?

    /// The `--timeout` this run was configured with, which no mutant is given less than.
    let configuredTimeout: Double

    /// Seconds a run of the tests an XCTest selection names may take. `nil` selects the whole
    /// suite, which is what a mutant with no narrower selection runs.
    func seconds(forSelection selection: String?) -> Double {
        guard let baseline else { return configuredTimeout }

        return max(configuredTimeout, Self.baselineCoefficient * baseline.duration(ofSelection: selection))
    }
}
