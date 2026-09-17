import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("BaselineReport")
struct BaselineReportTests {
    @Test("Given a mutant killed by a changed test, when scoping, then its line is in scope")
    func mutantKilledByChangedTestIsInScope() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = try writeReport(mutants: [(line: 42, killedBy: "FooTests.testSomething")], in: dir)

        let scope = try BaselineReport(path: path).scope(killedByTestsIn: ["/p/Tests/FooTests.swift"])

        #expect(scope.contains(filePath: "/p/Sources/Bar.swift", line: 42))
    }

    @Test("Given a mutant killed by an unchanged test, when scoping, then it is not in scope")
    func mutantKilledByUnchangedTestIsNotInScope() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = try writeReport(mutants: [(line: 42, killedBy: "OtherTests.testSomething")], in: dir)

        let scope = try BaselineReport(path: path).scope(killedByTestsIn: ["/p/Tests/FooTests.swift"])

        #expect(scope.isEmpty)
    }

    @Test("Given a survived mutant, when scoping, then it is not put in scope by a changed test")
    func survivedMutantIsNotInScope() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = try writeReport(mutants: [(line: 42, killedBy: nil)], in: dir)

        let scope = try BaselineReport(path: path).scope(killedByTestsIn: ["/p/Tests/FooTests.swift"])

        #expect(scope.isEmpty)
    }

    @Test("Given no changed test files, when scoping, then nothing is in scope")
    func noChangedTestsScopesNothing() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = try writeReport(mutants: [(line: 42, killedBy: "FooTests.testSomething")], in: dir)

        #expect(try BaselineReport(path: path).scope(killedByTestsIn: []).isEmpty)
    }

    @Test("Given a report that is not there, when read, then it throws a usage error")
    func missingReportThrowsUsageError() {
        #expect(throws: UsageError.self) { try BaselineReport(path: "/nonexistent/report.json") }
    }

    @Test("Given a file that is not a mutation report, when read, then it throws a usage error")
    func malformedReportThrowsUsageError() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileHelpers.write("not json", named: "report.json", in: dir)

        #expect(throws: UsageError.self) {
            try BaselineReport(path: dir.appendingPathComponent("report.json").path)
        }
    }

    private func writeReport(mutants: [(line: Int, killedBy: String?)], in directory: URL) throws -> String {
        let entries = mutants.map { mutant in
            """
            {
              "id": "swift-mutation-testing_0",
              "mutatorName": "BooleanLiteralReplacement",
              "originalText": "true",
              "replacement": "false",
              "location": {
                "start": { "line": \(mutant.line), "column": 9 },
                "end": { "line": \(mutant.line), "column": 13 }
              },
              "status": "\(mutant.killedBy == nil ? "Survived" : "Killed")",
              "description": "true -> false"
              \(mutant.killedBy.map { ", \"killedBy\": \"\($0)\"" } ?? "")
            }
            """
        }

        try FileHelpers.write(
            """
            {
              "schemaVersion": "1",
              "thresholds": { "high": 80, "low": 60 },
              "projectRoot": "/p",
              "files": {
                "/Sources/Bar.swift": {
                  "language": "swift",
                  "source": "let a = true",
                  "mutants": [\(entries.joined(separator: ","))]
                }
              }
            }
            """,
            named: "report.json",
            in: directory
        )

        return directory.appendingPathComponent("report.json").path
    }
}
