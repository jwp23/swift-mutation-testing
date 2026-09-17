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
        var candidate = Substring(line.trimmingCharacters(in: .whitespaces))

        if !candidate.hasPrefix("Test \""), let firstSpace = candidate.firstIndex(of: " ") {
            let glyph = candidate[..<firstSpace]
            if glyph.count == 1 {
                candidate = candidate[candidate.index(after: firstSpace)...]
            }
        }

        guard candidate.hasPrefix("Test \""), candidate.contains("\" failed") else { return nil }

        guard
            let start = candidate.range(of: "Test \"")?.upperBound,
            let end = candidate.range(of: "\" failed")?.lowerBound,
            start < end
        else { return nil }

        return String(candidate[start ..< end])
    }
}
