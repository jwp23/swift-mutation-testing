import Foundation

/// The file a named test was declared in. Callers hand it every file that belongs to the tests,
/// including the doubles and shared helpers among them; only the files that declare tests are
/// candidates, since a name is matched by reading content and a double is free to contain a
/// function of the same name as the test that uses it.
struct KillerTestFileResolver: Sendable {

    init(testFilePaths: [String]) {
        self.candidatePaths = testFilePaths.filter(TestFileConvention.declaresTests(path:))
    }

    private let candidatePaths: [String]

    func resolve(testName: String) -> String? {
        if let path = resolveXCTestClassName(testName) {
            return path
        }

        if let path = resolveSwiftTestingFunctionName(testName) {
            return path
        }

        return nil
    }

    private func resolveXCTestClassName(_ testName: String) -> String? {
        let className: String
        let components = testName.split(separator: ".")
        guard components.count >= 2 else { return nil }

        if components.count == 3 {
            className = String(components[1])
        } else {
            className = String(components[0])
        }

        let fileName = "\(className).swift"
        return candidatePaths.first { $0.hasSuffix("/\(fileName)") || $0 == fileName }
    }

    private func resolveSwiftTestingFunctionName(_ testName: String) -> String? {
        let components = testName.split(separator: "/")
        guard let lastComponent = components.last else { return nil }

        let functionName = String(lastComponent)

        for path in candidatePaths {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }

            if content.contains("func \(functionName)")
                || content.contains("@Test") && content.contains(functionName)
            {
                return path
            }
        }

        return nil
    }
}
