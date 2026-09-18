struct TestOutputParser: Sendable {
    enum Result: Sendable {
        case killed(by: String)
        case crashed
        case unviable
    }

    func parse(_ output: String) -> Result {
        var hasTestOutput = false

        for line in output.components(separatedBy: "\n") {
            if let name = failingTest(in: line) {
                return .killed(by: name)
            }

            if line.contains("Fatal error") || line.contains("EXC_BAD_INSTRUCTION") {
                return .crashed
            }

            if line.contains("Test Suite")
                || line.contains("Test run started")
                || line.contains("Testing started")
                || line.contains("** TEST FAILED **")
                || line.contains("Executed")
                || line.contains("◇ Suite")
                || line.contains("Test run with")
            {
                hasTestOutput = true
            }
        }

        return hasTestOutput ? .crashed : .unviable
    }

    /// The test a single line of output reports as failed, if it reports one. Exposed so a run read
    /// as it streams can recognise the first failure by the same rules a parse of the whole output
    /// uses.
    func failingTest(in line: String) -> String? {
        if let name = extractXCTestFailure(from: line) {
            return name
        }

        if let name = extractSwiftTestingFailure(from: line) {
            return name
        }

        return nil
    }

    private func extractXCTestFailure(from line: String) -> String? {
        let prefix = "Test Case '-["
        let suffix = "]' failed"

        guard line.contains(prefix), line.contains(suffix) else { return nil }

        guard
            let start = line.range(of: prefix)?.upperBound,
            let end = line.range(of: suffix)?.lowerBound,
            start < end
        else { return nil }

        let inner = String(line[start ..< end])
        let parts = inner.split(separator: " ", maxSplits: 1)

        guard parts.count == 2 else { return nil }

        return "\(parts[0]).\(parts[1])"
    }

    /// Requires the record to start the line — after trimming and stripping the single result
    /// glyph xcodebuild prefixes it with — rather than merely appearing anywhere in it, so a test
    /// or the app under test printing this phrase mid-sentence cannot be mistaken for the
    /// framework's own record.
    private func extractSwiftTestingFailure(from line: String) -> String? {
        let candidate = swiftTestingRecord(in: line)

        if let name = extractNamedSwiftTestingFailure(from: candidate) {
            return name
        }

        return extractSignatureSwiftTestingFailure(from: candidate)
    }

    private func swiftTestingRecord(in line: String) -> Substring {
        var candidate = Substring(line.trimmingCharacters(in: .whitespaces))

        if !candidate.hasPrefix("Test \""), let firstSpace = candidate.firstIndex(of: " ") {
            let glyph = candidate[..<firstSpace]
            if glyph.count == 1 {
                candidate = candidate[candidate.index(after: firstSpace)...]
            }
        }

        return candidate
    }

    /// A test given a custom display name (`@Test("...")`) reports its failure with that name
    /// quoted, e.g. `Test "some name" failed`.
    private func extractNamedSwiftTestingFailure(from candidate: Substring) -> String? {
        guard candidate.hasPrefix("Test \""), candidate.contains("\" failed") else { return nil }

        guard
            let start = candidate.range(of: "Test \"")?.upperBound,
            let end = candidate.range(of: "\" failed")?.lowerBound,
            start < end
        else { return nil }

        return String(candidate[start ..< end])
    }

    /// A test with no custom display name reports its failure by its function signature instead,
    /// unquoted, e.g. `Test plainExpectFailure() failed` or, for a parameterized test's rollup,
    /// `Test parameterized(value:) with 3 test cases failed`. Requiring the signature to contain
    /// a parenthesized parameter list (with no space before it) excludes run/suite-level rollups
    /// like `Test run with 3 tests in 1 suite failed`, which name no specific test.
    private func extractSignatureSwiftTestingFailure(from candidate: Substring) -> String? {
        guard candidate.hasPrefix("Test "), !candidate.hasPrefix("Test \"") else { return nil }

        let afterTest = candidate.dropFirst("Test ".count)

        guard
            let openParen = afterTest.firstIndex(of: "("),
            let closeParen = afterTest[openParen...].firstIndex(of: ")"),
            !afterTest[afterTest.startIndex ..< openParen].contains(" ")
        else { return nil }

        let signatureEnd = afterTest.index(after: closeParen)
        let words = afterTest[signatureEnd...].split(separator: " ")

        guard isFailureRollup(words) else { return nil }

        return String(afterTest[afterTest.startIndex ..< signatureEnd])
    }

    /// The words following a test's signature report either `failed ...` directly, or, for a
    /// parameterized test's rollup, `with <n> test case(s) failed ...`.
    private func isFailureRollup(_ words: [Substring]) -> Bool {
        if words.first == "failed" { return true }

        return words.count >= 5
            && words[0] == "with"
            && Int(words[1]) != nil
            && words[2] == "test"
            && (words[3] == "case" || words[3] == "cases")
            && words[4] == "failed"
    }
}
