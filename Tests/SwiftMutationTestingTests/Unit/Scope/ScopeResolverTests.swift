import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("ScopeResolver")
struct ScopeResolverTests {
    @Test("Given no scoping flag, when resolved, then the run is unscoped")
    func runWithoutScopingFlagsIsUnscoped() async throws {
        let resolver = ScopeResolver(launcher: MockProcessLauncher(exitCode: 0, producesTestBundle: false))

        let scope = try await resolver.resolve(configuration: makeRunnerConfiguration())

        #expect(scope == nil)
    }

    @Test("Given a line set flag, when resolved, then the scope covers those lines")
    func lineSetFlagScopesThoseLines() async throws {
        let resolver = ScopeResolver(launcher: MockProcessLauncher(exitCode: 0, producesTestBundle: false))

        let scope = try await resolver.resolve(
            configuration: makeRunnerConfiguration(scopeLines: ["Sources/Foo.swift:10-20"])
        )

        #expect(scope?.contains(filePath: "/p/Sources/Foo.swift", line: 12) == true)
        #expect(scope?.contains(filePath: "/p/Sources/Foo.swift", line: 21) == false)
    }

    @Test("Given a malformed line set flag, when resolved, then it throws a usage error")
    func malformedLineSetFlagThrows() async {
        let resolver = ScopeResolver(launcher: MockProcessLauncher(exitCode: 0, producesTestBundle: false))

        await #expect(throws: UsageError.self) {
            _ = try await resolver.resolve(configuration: makeRunnerConfiguration(scopeLines: ["Foo.swift"]))
        }
    }

    @Test("Given a baseline report without a scoping flag, when resolved, then it throws a usage error")
    func baselineReportWithoutScopingFlagThrows() async {
        let resolver = ScopeResolver(launcher: MockProcessLauncher(exitCode: 0, producesTestBundle: false))

        await #expect(throws: UsageError.self) {
            _ = try await resolver.resolve(configuration: makeRunnerConfiguration(baselineReport: "/p/report.json"))
        }
    }

    @Test("Given a reference, when resolved, then the scope covers the lines its diff changed")
    func referenceScopesChangedLines() async throws {
        let resolver = ScopeResolver(
            launcher: MockProcessLauncher(
                exitCode: 0,
                output: """
                    --- a/Sources/Foo.swift
                    +++ b/Sources/Foo.swift
                    @@ -4 +4,2 @@
                    +let a = 1
                    +let b = 2
                    """,
                producesTestBundle: false
            )
        )

        let scope = try await resolver.resolve(configuration: makeRunnerConfiguration(since: "main"))

        #expect(scope?.contains(filePath: "/p/Sources/Foo.swift", line: 5) == true)
        #expect(scope?.contains(filePath: "/p/Sources/Foo.swift", line: 6) == false)
    }

    @Test("Given a reference and a line set, when resolved, then the scope covers both")
    func referenceAndLineSetCompose() async throws {
        let resolver = ScopeResolver(
            launcher: MockProcessLauncher(
                exitCode: 0,
                output: """
                    --- a/Sources/Foo.swift
                    +++ b/Sources/Foo.swift
                    @@ -4 +4 @@
                    +let a = 1
                    """,
                producesTestBundle: false
            )
        )

        let scope = try await resolver.resolve(
            configuration: makeRunnerConfiguration(scopeLines: ["Sources/Bar.swift:1-2"], since: "main")
        )

        #expect(scope?.contains(filePath: "/p/Sources/Foo.swift", line: 4) == true)
        #expect(scope?.contains(filePath: "/p/Sources/Bar.swift", line: 1) == true)
    }

    @Test("Given a changed test file, when resolved, then the source it covers is wholly in scope")
    func changedTestFileScopesItsSource() async throws {
        let resolver = ScopeResolver(launcher: changedTestFileLauncher())

        let scope = try await resolver.resolve(configuration: makeRunnerConfiguration(since: "main"))

        #expect(scope?.contains(filePath: "/p/Sources/Foo.swift", line: 1) == true)
        #expect(scope?.contains(filePath: "/p/Sources/Foo.swift", line: 900) == true)
    }

    @Test("Given a changed test file with an override, when resolved, then the overridden source is in scope")
    func changedTestFileScopesItsOverriddenSource() async throws {
        let resolver = ScopeResolver(launcher: changedTestFileLauncher())

        let scope = try await resolver.resolve(
            configuration: makeRunnerConfiguration(
                since: "main",
                likelyKillerTests: ["App/Minutes.swift": ["FooTests.swift"]]
            )
        )

        #expect(scope?.contains(filePath: "/p/App/Minutes.swift", line: 7) == true)
    }

    @Test("Given a changed test under a Tests directory, when resolved, then the source it covers is in scope")
    func changedTestInTestsDirectoryScopesItsSource() async throws {
        let resolver = ScopeResolver(launcher: changedDirectoryTestFileLauncher())

        let scope = try await resolver.resolve(
            configuration: makeRunnerConfiguration(
                projectPath: "/p",
                since: "main",
                likelyKillerTests: ["App/Login.swift": ["LoginFlow.swift"]]
            )
        )

        #expect(scope?.contains(filePath: "/p/App/Login.swift", line: 7) == true)
    }

    @Test("Given a changed test under a Tests directory, when resolved, then the mutants it killed are in scope")
    func changedTestInTestsDirectoryScopesTheMutantsItKilled() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let reportPath = try writeBaselineReport(in: dir, killedBy: "LoginFlow.testSignIn")
        let resolver = ScopeResolver(launcher: changedDirectoryTestFileLauncher())

        let scope = try await resolver.resolve(
            configuration: makeRunnerConfiguration(projectPath: "/p", since: "main", baselineReport: reportPath)
        )

        #expect(scope?.contains(filePath: "/p/Sources/Bar.swift", line: 42) == true)
    }

    @Test("Given a deleted test file, when resolved, then the source it covered is wholly in scope")
    func deletedTestFileScopesItsSource() async throws {
        let resolver = ScopeResolver(
            launcher: MockProcessLauncher(
                exitCode: 0,
                output: """
                    --- a/Tests/FooTests.swift
                    +++ /dev/null
                    @@ -1,20 +0,0 @@
                    -import XCTest
                    """,
                producesTestBundle: false
            )
        )

        let scope = try await resolver.resolve(configuration: makeRunnerConfiguration(since: "main"))

        #expect(scope?.contains(filePath: "/p/Sources/Foo.swift", line: 12) == true)
    }

    @Test("Given a changed source file, when resolved, then only its changed lines are in scope")
    func changedSourceFileIsNotReadAsATest() async throws {
        let resolver = ScopeResolver(
            launcher: MockProcessLauncher(
                exitCode: 0,
                output: """
                    --- a/Sources/Foo.swift
                    +++ b/Sources/Foo.swift
                    @@ -4 +4 @@
                    +let a = 1
                    """,
                producesTestBundle: false
            )
        )

        let scope = try await resolver.resolve(configuration: makeRunnerConfiguration(since: "main"))

        #expect(scope?.contains(filePath: "/p/Sources/Foo.swift", line: 900) == false)
    }

    @Test("Given a baseline report, when a test changed, then the mutants it killed elsewhere are in scope")
    func changedTestFileScopesTheMutantsItKilled() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let reportPath = try writeBaselineReport(in: dir)
        let resolver = ScopeResolver(launcher: changedTestFileLauncher())

        let scope = try await resolver.resolve(
            configuration: makeRunnerConfiguration(since: "main", baselineReport: reportPath)
        )

        #expect(scope?.contains(filePath: "/p/Sources/Bar.swift", line: 42) == true)
        #expect(scope?.contains(filePath: "/p/Sources/Bar.swift", line: 43) == false)
    }

    /// A diff that changes one test file whose only mark of being a test is the directory it lives
    /// in — the shape a diff takes for most of a project's tests.
    private func changedDirectoryTestFileLauncher() -> MockProcessLauncher {
        MockProcessLauncher(
            exitCode: 0,
            output: """
                --- a/Tests/AppTests/LoginFlow.swift
                +++ b/Tests/AppTests/LoginFlow.swift
                @@ -4 +4 @@
                +    XCTAssertTrue(true)
                """,
            producesTestBundle: false
        )
    }

    /// A diff that changes one test file, and nothing else.
    private func changedTestFileLauncher() -> MockProcessLauncher {
        MockProcessLauncher(
            exitCode: 0,
            output: """
                --- a/Tests/FooTests.swift
                +++ b/Tests/FooTests.swift
                @@ -4 +4 @@
                +    XCTAssertTrue(true)
                """,
            producesTestBundle: false
        )
    }

    private func writeBaselineReport(in directory: URL, killedBy: String = "FooTests.testSomething") throws -> String {
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
                  "mutants": [
                    {
                      "id": "swift-mutation-testing_0",
                      "mutatorName": "BooleanLiteralReplacement",
                      "originalText": "true",
                      "replacement": "false",
                      "location": {
                        "start": { "line": 42, "column": 9 },
                        "end": { "line": 42, "column": 13 }
                      },
                      "status": "Killed",
                      "description": "true -> false",
                      "killedBy": "\(killedBy)"
                    }
                  ]
                }
              }
            }
            """,
            named: "baseline.json",
            in: directory
        )

        return directory.appendingPathComponent("baseline.json").path
    }
}
