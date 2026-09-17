import Foundation

/// The mutants a schema build cannot compile. One generated case the compiler rejects fails the
/// whole build, so the errors are read back to the cases they name and those cases are cut out of
/// the sandbox's copy of the source, leaving a build that compiles without them. Every mutant cut
/// out this way is handed back to be tested from a build of its own rather than lost.
enum UncompilableMutants {

    /// The sandbox source files the compiler reported errors in.
    static func erroringSourcePaths(in output: String, sandboxRoot: String) -> Set<String> {
        Set(
            output.components(separatedBy: "\n").compactMap { line -> String? in
                guard line.hasPrefix(sandboxRoot) else { return nil }
                let path = line.components(separatedBy: ":").first ?? ""
                return path.hasSuffix(".swift") ? path : nil
            }
        )
    }

    /// Cuts the mutant cases this file's compile errors name out of the sandbox's copy of it, and
    /// answers the mutants cut out. Errors that cannot be traced to any mutant case are not this
    /// file's schematization to narrow, so the sandbox goes back to the original source and the
    /// file gives up every mutant it holds.
    static func removeFromSandbox(
        sandboxPath: String,
        originalPath: String,
        errorOutput: String,
        mutantsInFile: [MutantDescriptor]
    ) -> [MutantDescriptor] {
        let errorLines = Set(
            errorOutput.components(separatedBy: "\n").compactMap { line -> Int? in
                guard line.hasPrefix(sandboxPath + ":") else { return nil }
                let remainder = String(line.dropFirst(sandboxPath.count + 1))
                return remainder.components(separatedBy: ":").first.flatMap { Int($0) }
            }
        )

        guard
            !errorLines.isEmpty,
            let content = try? String(contentsOfFile: sandboxPath, encoding: .utf8)
        else {
            restoreOriginal(sandboxPath: sandboxPath, originalPath: originalPath)
            return mutantsInFile
        }

        let lines = content.components(separatedBy: "\n")
        let mutantIDs = Set(mutantsInFile.map(\.id))
        var problematicIDs = Set<String>()

        for errorLine in errorLines {
            let lineIndex = errorLine - 1
            guard lineIndex >= 0, lineIndex < lines.count else { continue }
            var searchIndex = lineIndex
            while searchIndex >= 0 {
                let trimmed = lines[searchIndex].trimmingCharacters(in: .whitespaces)
                if let id = mutantCaseID(from: trimmed), mutantIDs.contains(id) {
                    problematicIDs.insert(id)
                    break
                }
                if trimmed == "default:" || trimmed.hasPrefix("switch ") { break }
                searchIndex -= 1
            }
        }

        guard !problematicIDs.isEmpty else {
            restoreOriginal(sandboxPath: sandboxPath, originalPath: originalPath)
            return mutantsInFile
        }

        let narrowed = removingCases(problematicIDs, from: lines)
        try? narrowed.write(toFile: sandboxPath, atomically: true, encoding: .utf8)

        let excluded = mutantsInFile.filter { problematicIDs.contains($0.id) }
        return excluded
    }

    private static func restoreOriginal(sandboxPath: String, originalPath: String) {
        try? FileManager.default.removeItem(atPath: sandboxPath)
        try? FileManager.default.createSymbolicLink(atPath: sandboxPath, withDestinationPath: originalPath)
    }

    private static func mutantCaseID(from trimmedLine: String) -> String? {
        let casePrefix = "case \""
        let caseSuffix = "\":"
        guard trimmedLine.hasPrefix(casePrefix), trimmedLine.hasSuffix(caseSuffix) else { return nil }
        let id = String(trimmedLine.dropFirst(casePrefix.count).dropLast(caseSuffix.count))
        return id.hasPrefix("swift-mutation-testing_") ? id : nil
    }

    private static func removingCases(_ ids: Set<String>, from lines: [String]) -> String {
        var result: [String] = []
        var skipping = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let id = mutantCaseID(from: trimmed) {
                skipping = ids.contains(id)
                if !skipping { result.append(line) }
            } else if skipping {
                if trimmed == "default:" || mutantCaseID(from: trimmed) != nil {
                    skipping = false
                    result.append(line)
                }
            } else {
                result.append(line)
            }
        }

        return result.joined(separator: "\n")
    }
}
