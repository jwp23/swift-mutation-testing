/// The lines a unified diff leaves changed on its new side, as a scope over the files it names.
///
/// Reads the zero-context form `git diff -U0` produces, where a hunk header already covers exactly
/// the changed lines and no context line has to be counted.
///
/// A file the diff deletes goes into the scope whole. It has no lines left to mutate, so nothing is
/// discovered in it either way — but a deleted test file still has to put the source it covered back
/// in scope, and a deletion is the change most likely to leave a mutant unwatched.
struct GitDiffParser: Sendable {
    private static let oldFileMarker = "--- "
    private static let newFileMarker = "+++ "
    private static let hunkMarker = "@@"

    /// The byte a single-character escape (`\n`, `\"`, ...) stands for, keyed by the character
    /// git writes after the backslash.
    private static let simpleEscapes: [Character: UInt8] = [
        "\"": 0x22, "\\": 0x5C, "a": 0x07, "b": 0x08, "f": 0x0C,
        "n": 0x0A, "r": 0x0D, "t": 0x09, "v": 0x0B,
    ]

    func parse(_ diff: String) -> MutantScope {
        var lineRangesByPath: [String: [ClosedRange<Int>]] = [:]
        var deletedPath: String?
        var path: String?

        for line in diff.components(separatedBy: "\n") {
            if line.hasPrefix(Self.oldFileMarker) {
                deletedPath = strippedPath(in: line, after: Self.oldFileMarker, prefixedBy: "a/")
            } else if line.hasPrefix(Self.newFileMarker) {
                path = newSidePath(in: line)
                if path == nil, let deletedPath {
                    lineRangesByPath[deletedPath] = [MutantScope.everyLine]
                }
            } else if line.hasPrefix(Self.hunkMarker), let path, let range = changedLines(in: line) {
                lineRangesByPath[path, default: []].append(range)
            }
        }

        return MutantScope(lineRangesByPath: lineRangesByPath)
    }

    /// The path the new side of a diff names, or nil for a file the diff deletes.
    private func newSidePath(in line: String) -> String? {
        strippedPath(in: line, after: Self.newFileMarker, prefixedBy: "b/")
    }

    /// The path a file marker names, without the prefix a diff gives each side unless it was asked
    /// not to, and nil for the marker that stands for no file at all.
    private func strippedPath(in line: String, after marker: String, prefixedBy prefix: String) -> String? {
        let raw = String(line.dropFirst(marker.count))

        guard raw != "/dev/null" else { return nil }

        let path = unquoted(raw)

        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    /// Undoes the C-quoting `git diff` wraps a path in when it holds a quote, a backslash, a
    /// control character, or — unless `core.quotepath` is off — a non-ASCII byte. A path git had
    /// no reason to quote is returned unchanged.
    private func unquoted(_ path: String) -> String {
        guard path.hasPrefix("\""), path.hasSuffix("\""), path.count >= 2 else { return path }

        var bytes: [UInt8] = []
        var characters = path.dropFirst().dropLast().makeIterator()

        while let character = characters.next() {
            guard character == "\\" else {
                bytes.append(contentsOf: String(character).utf8)
                continue
            }

            guard let escape = characters.next() else { break }

            bytes.append(contentsOf: escapedBytes(for: escape, remaining: &characters))
        }

        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    /// The bytes one escape sequence stands for, reading further octal digits off `remaining`
    /// when `escape` starts an `\ooo` byte value rather than a single-character escape.
    private func escapedBytes<Characters: IteratorProtocol>(
        for escape: Character,
        remaining characters: inout Characters
    ) -> [UInt8] where Characters.Element == Character {
        if let byte = Self.simpleEscapes[escape] { return [byte] }

        var octal = String(escape)

        while octal.count < 3, let digit = characters.next() {
            octal.append(digit)
        }

        guard let value = UInt8(octal, radix: 8) else { return [] }

        return [value]
    }

    /// The new-side lines a hunk header covers, or nil for a hunk that only deletes lines and so
    /// leaves nothing behind to mutate.
    private func changedLines(in header: String) -> ClosedRange<Int>? {
        guard
            let newSide = header.components(separatedBy: " ").first(where: { $0.hasPrefix("+") })
        else { return nil }

        let fields = newSide.dropFirst().components(separatedBy: ",")
        let count = fields.count > 1 ? Int(fields[1]) : 1

        guard let start = Int(fields[0]), let count, count > 0 else { return nil }

        return start ... (start + count - 1)
    }
}
