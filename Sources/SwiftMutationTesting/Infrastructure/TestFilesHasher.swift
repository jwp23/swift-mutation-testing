import Foundation

struct TestFilesHasher: Sendable {

    func hashPerFile(projectPath: String) -> [String: String] {
        let paths = collectTestFilePaths(under: URL(fileURLWithPath: projectPath))
        var result: [String: String] = [:]

        for path in paths.sorted() {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }

            let relativePath = PathRelativizer.relativePath(for: path, relativeTo: projectPath)
            result[relativePath] = MutantCacheKey.hash(of: content)
        }

        return result
    }

    func testFilePaths(projectPath: String) -> [String] {
        collectTestFilePaths(under: URL(fileURLWithPath: projectPath))
    }

    private func collectTestFilePaths(under directory: URL) -> [String] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        var paths: [String] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }

            if TestFileConvention.isTestFile(path: url.path) {
                paths.append(url.path)
            }
        }

        return paths
    }
}
