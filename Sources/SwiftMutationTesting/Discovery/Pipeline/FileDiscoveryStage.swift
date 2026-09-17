import Foundation

struct FileDiscoveryStage: Sendable {
    func run(input: DiscoveryInput) throws -> [SourceFile] {
        let url = URL(fileURLWithPath: input.sourcesPath)

        guard FileManager.default.fileExists(atPath: input.sourcesPath) else {
            throw FileDiscoveryError.sourcesPathNotFound(input.sourcesPath)
        }

        guard
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else { throw FileDiscoveryError.sourcesPathNotFound(input.sourcesPath) }

        let exclusion = SourceFileExclusion(patterns: input.excludePatterns)
        var sourceFiles: [SourceFile] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else {
                continue
            }

            let path = fileURL.path

            guard !exclusion.excludes(path: path) else {
                continue
            }

            // A file the scope does not reach can hold no mutant the scope would keep, so a scoped
            // run never pays to read or parse it.
            guard input.scope?.covers(filePath: path) ?? true else {
                continue
            }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }

            sourceFiles.append(SourceFile(path: path, content: content))
        }

        return sourceFiles
    }
}
