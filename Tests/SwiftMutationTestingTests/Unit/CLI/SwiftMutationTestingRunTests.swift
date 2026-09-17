import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SwiftMutationTesting.run")
struct SwiftMutationTestingRunTests {
    @Test("Given --help flag, when run called, then returns success")
    func helpFlagReturnsSuccess() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let result = await SwiftMutationTesting.run(args: ["--help"])

        #expect(result == .success)
    }

    @Test("Given --help flag, when run called, then prints usage to stdout")
    func helpFlagPrintsUsage() async {
        let output = await captureOutput {
            _ = await SwiftMutationTesting.run(args: ["--help"])
        }

        #expect(output.contains("swift-mutation-testing"))
    }

    @Test("Given --version flag, when run called, then returns success")
    func versionFlagReturnsSuccess() async {
        let result = await SwiftMutationTesting.run(args: ["--version"])

        #expect(result == .success)
    }

    @Test("Given --version flag, when run called, then prints version to stdout")
    func versionFlagPrintsVersion() async {
        let output = await captureOutput {
            _ = await SwiftMutationTesting.run(args: ["--version"])
        }

        #expect(output.contains("swift-mutation-testing"))
    }

    @Test("Given no scheme, when run called, then returns error")
    func missingSchemeReturnsError() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let result = await SwiftMutationTesting.run(args: [dir.path])

        #expect(result == .error)
    }

    @Test("Given scheme but no destination, when run called, then returns error")
    func missingDestinationReturnsError() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let result = await SwiftMutationTesting.run(args: [dir.path, "--scheme", "App"])

        #expect(result == .error)
    }

    @Test("Given unknown flag, when run called, then returns error")
    func unknownFlagReturnsError() async {
        let result = await SwiftMutationTesting.run(args: ["--unknown-flag-xyz"])

        #expect(result == .error)
    }

    @Test("Given init command on empty directory, when run called, then returns success and creates yml")
    func initCommandCreatesConfigFile() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let result = await SwiftMutationTesting.run(args: ["init", dir.path])

        #expect(result == .success)
        let ymlPath = dir.appendingPathComponent(".swift-mutation-testing.yml").path
        #expect(FileManager.default.fileExists(atPath: ymlPath))
    }

    @Test("Given init command when yml already exists, when run called, then returns error")
    func initCommandFailsWhenYmlExists() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let ymlURL = dir.appendingPathComponent(".swift-mutation-testing.yml")
        try "existing".write(to: ymlURL, atomically: true, encoding: .utf8)

        let result = await SwiftMutationTesting.run(args: ["init", dir.path])

        #expect(result == .error)
    }

    @Test("Given a scope holding no mutant, when run called, then it passes without building")
    func emptyScopePassesWithoutBuilding() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileHelpers.write("// swift-tools-version:6.0", named: "Package.swift", in: dir)
        try FileHelpers.write("func f() { let x = true }", named: "Source.swift", in: dir)

        let launcher = RecordingProcessLauncher()
        var result: ExitCode?
        let output = await captureOutput {
            result = await SwiftMutationTesting.run(
                args: [dir.path, "--scope-lines", "Absent.swift:1-2", "--quiet"],
                launcher: launcher
            )
        }

        #expect(result == .success)
        #expect(output.contains("No mutants in scope"))
        #expect(await launcher.requests.isEmpty)
    }

    @Test("Given a scope holding no mutant, when run called, then the scope it resolved is printed")
    func emptyScopeIsPrintedSoATypoIsVisible() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileHelpers.write("// swift-tools-version:6.0", named: "Package.swift", in: dir)
        try FileHelpers.write("func f() { let x = true }", named: "Source.swift", in: dir)

        let output = await captureOutput {
            _ = await SwiftMutationTesting.run(
                args: [dir.path, "--scope-lines", "Absent.swift:1-2", "--quiet"],
                launcher: RecordingProcessLauncher()
            )
        }

        #expect(output.contains("Scope: Absent.swift:1-2"))
    }

    @Test("Given a scope holding no mutant and a report path, when run called, then the report is still written")
    func emptyScopeStillWritesItsReport() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileHelpers.write("// swift-tools-version:6.0", named: "Package.swift", in: dir)
        try FileHelpers.write("func f() { let x = true }", named: "Source.swift", in: dir)
        let reportPath = dir.appendingPathComponent("report.json").path

        let output = await captureOutput {
            _ = await SwiftMutationTesting.run(
                args: [dir.path, "--scope-lines", "Absent.swift:1-2", "--quiet", "--output", reportPath],
                launcher: RecordingProcessLauncher()
            )
        }

        #expect(output.contains("JSON report"))
        #expect(FileManager.default.fileExists(atPath: reportPath))
    }
}
