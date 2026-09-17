import Foundation

struct ConfigurationFileParser: Sendable {
    /// Key prefix each entry of the `likely-killer-tests` mapping is flattened under, so that a
    /// nested block still fits the flat key-value shape the resolver reads.
    static let likelyKillerTestsPrefix = "likely-killer-tests."

    /// A nested block whose lines mean something other than a list item under the last key.
    private enum Block {
        case mutators
        case likelyKillerTests
    }

    func parse(at projectPath: String) throws -> [String: String] {
        let fileURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".swift-mutation-testing.yml")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        var result: [String: String] = [:]
        var lastKey: String?
        var listValues: [String: [String]] = [:]
        var block: Block?
        var currentMutatorName: String?
        var disabledMutators: [String] = []

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let indent = line.prefix(while: { $0 == " " }).count

            if indent == 0 {
                block = nil
                currentMutatorName = nil
                parseTopLevel(trimmed, result: &result, lastKey: &lastKey, block: &block)
                continue
            }

            switch block {
            case .mutators:
                parseMutatorLine(trimmed, currentName: &currentMutatorName, disabled: &disabledMutators)

            case .likelyKillerTests:
                parseLikelyKillerTestsLine(trimmed, result: &result)

            case nil:
                if trimmed.hasPrefix("- "), let key = lastKey {
                    let item = String(trimmed.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    listValues[key, default: []].append(item)
                }
            }
        }

        for (key, items) in listValues {
            result[key] = items.joined(separator: ",")
        }

        if !disabledMutators.isEmpty {
            result["disabled-mutators"] = disabledMutators.joined(separator: ",")
        }

        return result
    }

    private func parseTopLevel(
        _ trimmed: String,
        result: inout [String: String],
        lastKey: inout String?,
        block: inout Block?
    ) {
        guard let colonIndex = trimmed.firstIndex(of: ":") else { return }
        let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        let rawValue = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        let value = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !key.isEmpty else { return }
        lastKey = key
        if key == "mutators" {
            block = .mutators
        } else if key == "likely-killer-tests" {
            block = .likelyKillerTests
        } else if !value.isEmpty {
            result[key] = value
        }
    }

    /// One `Source.swift: ATests.swift, BTests.swift` entry of the `likely-killer-tests` mapping,
    /// flattened onto a key of its own so the mapping survives as flat key-value pairs.
    private func parseLikelyKillerTestsLine(_ trimmed: String, result: inout [String: String]) {
        guard let colonIndex = trimmed.firstIndex(of: ":") else { return }
        let source = String(trimmed[..<colonIndex])
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        let tests = String(trimmed[trimmed.index(after: colonIndex)...])
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        guard !source.isEmpty, !tests.isEmpty else { return }

        result[Self.likelyKillerTestsPrefix + source] = tests
    }

    private func parseMutatorLine(
        _ trimmed: String,
        currentName: inout String?,
        disabled: inout [String]
    ) {
        if trimmed.hasPrefix("- name:") {
            currentName = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        } else if trimmed.hasPrefix("active: false"), let name = currentName {
            disabled.append(name)
        }
    }
}
