/// The source lines a run is limited to. A mutant is in scope when one of the scope's paths names
/// its file and one of that path's ranges covers its line.
///
/// Scope paths arrive from a diff or a command line, where a file is named relative to the project,
/// while discovery knows files by their absolute path. A scope path therefore matches a file it is
/// a trailing run of whole path components of, which also lets a bare file name stand for that file
/// wherever the project keeps it.
///
/// An unscoped run has no `MutantScope` at all, so an empty scope means nothing is in scope rather
/// than everything.
struct MutantScope: Sendable, Equatable, CustomStringConvertible {
    init(lineRangesByPath: [String: [ClosedRange<Int>]]) {
        self.lineRangesByPath = Dictionary(
            lineRangesByPath.map { (Self.normalized($0.key), $0.value) },
            uniquingKeysWith: { $0 + $1 }
        )
    }

    /// Every line of a file, for a path put in scope whole rather than by the lines a diff changed.
    static let everyLine: ClosedRange<Int> = 1 ... Int.max

    private let lineRangesByPath: [String: [ClosedRange<Int>]]

    /// What the scope came to, for a run to print. A scope is computed from flags and a diff rather
    /// than written out by hand, so the lines it ended up covering are the only way to tell a change
    /// that really touches no mutant from a path that was mistyped and matched nothing.
    var description: String {
        guard !isEmpty else { return "nothing" }

        return
            lineRangesByPath
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\(describe($0.value))" }
            .joined(separator: ", ")
    }

    var isEmpty: Bool {
        lineRangesByPath.isEmpty
    }

    /// The paths the scope was built from, which the resolver reads back to find the test files a
    /// diff changed.
    var paths: [String] {
        Array(lineRangesByPath.keys)
    }

    /// A scope path with its `.` components and repeated separators collapsed, so `./Foo.swift`
    /// and `Sources//Foo.swift` match the same file a plain relative path would. A path a user or
    /// a diff wrote by hand can carry either without meaning anything different by it.
    private static func normalized(_ path: String) -> String {
        let isAbsolute = path.hasPrefix("/")
        let components = path.split(separator: "/").filter { $0 != "." }
        let joined = components.joined(separator: "/")

        return isAbsolute ? "/" + joined : joined
    }

    /// Whether the scope covers any line of `filePath` — the question discovery asks before
    /// spending a parse on a file. It costs nothing in accuracy: a file the scope does not name can
    /// hold no mutant the line filter would keep.
    func covers(filePath: String) -> Bool {
        !ranges(for: filePath).isEmpty
    }

    /// Whether a mutant at `line` of `filePath` is one this run tests.
    func contains(filePath: String, line: Int) -> Bool {
        ranges(for: filePath).contains { $0.contains(line) }
    }

    /// A scope covering every line either scope covers.
    func union(_ other: MutantScope) -> MutantScope {
        MutantScope(lineRangesByPath: lineRangesByPath.merging(other.lineRangesByPath) { $0 + $1 })
    }

    private func describe(_ ranges: [ClosedRange<Int>]) -> String {
        ranges
            .map { $0 == Self.everyLine ? "all" : "\($0.lowerBound)-\($0.upperBound)" }
            .joined(separator: ",")
    }

    private func ranges(for filePath: String) -> [ClosedRange<Int>] {
        lineRangesByPath
            .filter { filePath == $0.key || filePath.hasSuffix("/\($0.key)") }
            .flatMap(\.value)
    }
}
