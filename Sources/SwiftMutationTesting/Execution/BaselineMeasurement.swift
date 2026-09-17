/// What the unmutated suite costs to run, measured once before any mutant is tested.
///
/// It is what a mutant's timeout is judged against: a mutant runs the same tests the baseline
/// did, so the time those tests took unmutated is the only honest scale for how long the mutant's
/// own run may take.
struct BaselineMeasurement: Sendable {
    /// Wall clock the whole unmutated run took, across every bundle it ran. Unlike the per-test
    /// durations it also covers what the run pays outside its tests — starting the process,
    /// standing the suite up — which a mutant's run pays too.
    let totalDuration: Double

    /// Seconds each test took, keyed the way an XCTest selection names it: `Class/method`, without
    /// the module prefix XCTest prints.
    let testDurations: [String: Double]

    /// Seconds the tests an XCTest selection names took unmutated. A run that selects nothing runs
    /// the whole suite, and so does one whose selection no measured test matched — a selection the
    /// baseline cannot account for is given the whole run's time rather than none of it.
    func duration(ofSelection selection: String?) -> Double {
        guard let selection else { return totalDuration }

        let selected = selection.components(separatedBy: ",").flatMap(durations(ofComponent:))

        return selected.isEmpty ? totalDuration : selected.reduce(0, +)
    }

    /// Durations of the tests one component of a selection names: a single test when it names a
    /// method, every test of the class when it names only a class.
    private func durations(ofComponent component: String) -> [Double] {
        guard !component.contains("/") else {
            return testDurations[component].map { [$0] } ?? []
        }

        return testDurations.filter { $0.key.hasPrefix("\(component)/") }.map(\.value)
    }
}
