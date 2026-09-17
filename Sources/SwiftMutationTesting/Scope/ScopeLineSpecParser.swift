/// Reads the `path:start-end` line sets the `--scope-lines` flag takes, the form every other way of
/// scoping a run is expressed in before it reaches discovery.
struct ScopeLineSpecParser: Sendable {
    func parse(_ specs: [String]) throws -> MutantScope {
        var lineRangesByPath: [String: [ClosedRange<Int>]] = [:]

        for spec in specs {
            let lineSet = try lineSet(from: spec)
            lineRangesByPath[lineSet.path, default: []].append(lineSet.lines)
        }

        return MutantScope(lineRangesByPath: lineRangesByPath)
    }

    /// The path and lines one spec names. The path is taken up to the last colon, so a path that
    /// contains one is still read whole.
    private func lineSet(from spec: String) throws -> (path: String, lines: ClosedRange<Int>) {
        guard let separator = spec.lastIndex(of: ":") else {
            throw malformed(spec)
        }

        let path = String(spec[spec.startIndex ..< separator])
        let bounds = spec[spec.index(after: separator)...].components(separatedBy: "-")

        guard
            !path.isEmpty,
            bounds.count == 2,
            let start = Int(bounds[0]),
            let end = Int(bounds[1]),
            start >= 1,
            start <= end
        else {
            throw malformed(spec)
        }

        return (path, start ... end)
    }

    private func malformed(_ spec: String) -> UsageError {
        UsageError(message: "--scope-lines must be 'path:start-end', got '\(spec)'")
    }
}
