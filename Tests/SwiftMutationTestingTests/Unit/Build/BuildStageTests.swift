import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("BuildStage")
struct BuildStageTests {
    @Test("Given successful build and xctestrun present, when build called, then returns BuildArtifact")
    func returnsArtifactOnSuccess() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let productsDir = projectDir.appendingPathComponent(".xmr-derived-data/Build/Products")
        try FileManager.default.createDirectory(at: productsDir, withIntermediateDirectories: true)

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: ["__xctestrun_metadata__": ["FormatVersion": 1]],
            format: .xml,
            options: 0
        )
        try plistData.write(to: productsDir.appendingPathComponent("App.xctestrun"))

        let sandbox = Sandbox(rootURL: projectDir)
        let stage = BuildStage(launcher: MockProcessLauncher(exitCode: 0))

        let artifact = try await stage.build(
            sandbox: sandbox,
            scheme: "App",
            destination: "platform=macOS,arch=arm64",
            timeout: 60
        )

        #expect(artifact.derivedDataPath == projectDir.appendingPathComponent(".xmr-derived-data").path)
        #expect(artifact.xctestrunURL?.lastPathComponent == "App.xctestrun")
    }

    @Test("Given build failure, when build called, then throws compilationFailed")
    func throwsCompilationFailedOnNonZeroExitCode() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let sandbox = Sandbox(rootURL: projectDir)
        let stage = BuildStage(launcher: MockProcessLauncher(exitCode: 1))

        await #expect {
            try await stage.build(
                sandbox: sandbox,
                scheme: "App",
                destination: "platform=macOS,arch=arm64",
                timeout: 60
            )
        } throws: { error in
            guard case BuildError.compilationFailed = error else { return false }
            return true
        }
    }

    @Test("Given xcworkspace in sandbox, when build called, then workspace flag is passed")
    func usesWorkspaceFlagWhenXcworkspacePresent() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        try FileManager.default.createDirectory(
            at: projectDir.appendingPathComponent("MyApp.xcworkspace"),
            withIntermediateDirectories: true
        )
        let productsDir = projectDir.appendingPathComponent(".xmr-derived-data/Build/Products")
        try FileManager.default.createDirectory(at: productsDir, withIntermediateDirectories: true)

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: ["__xctestrun_metadata__": ["FormatVersion": 1]],
            format: .xml, options: 0
        )
        try plistData.write(to: productsDir.appendingPathComponent("App.xctestrun"))

        let sandbox = Sandbox(rootURL: projectDir)
        let stage = BuildStage(launcher: MockProcessLauncher(exitCode: 0))

        let artifact = try await stage.build(
            sandbox: sandbox, scheme: "App", destination: "platform=macOS", timeout: 60
        )

        #expect(artifact.xctestrunURL?.lastPathComponent == "App.xctestrun")
    }

    @Test("Given xcodeproj in sandbox, when build called, then project flag is passed")
    func usesProjectFlagWhenXcodeprojPresent() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        try FileManager.default.createDirectory(
            at: projectDir.appendingPathComponent("MyApp.xcodeproj"),
            withIntermediateDirectories: true
        )
        let productsDir = projectDir.appendingPathComponent(".xmr-derived-data/Build/Products")
        try FileManager.default.createDirectory(at: productsDir, withIntermediateDirectories: true)

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: ["__xctestrun_metadata__": ["FormatVersion": 1]],
            format: .xml, options: 0
        )
        try plistData.write(to: productsDir.appendingPathComponent("App.xctestrun"))

        let sandbox = Sandbox(rootURL: projectDir)
        let stage = BuildStage(launcher: MockProcessLauncher(exitCode: 0))

        let artifact = try await stage.build(
            sandbox: sandbox, scheme: "App", destination: "platform=macOS", timeout: 60
        )

        #expect(artifact.xctestrunURL?.lastPathComponent == "App.xctestrun")
    }

    @Test("Given xctestrun file with invalid plist data, when build called, then throws xctestrunNotFound")
    func throwsXctestrunNotFoundForInvalidPlist() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let productsDir = projectDir.appendingPathComponent(".xmr-derived-data/Build/Products")
        try FileManager.default.createDirectory(at: productsDir, withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: productsDir.appendingPathComponent("App.xctestrun"))

        let sandbox = Sandbox(rootURL: projectDir)
        let stage = BuildStage(launcher: MockProcessLauncher(exitCode: 0))

        await #expect(throws: BuildError.xctestrunNotFound) {
            try await stage.build(
                sandbox: sandbox, scheme: "App", destination: "platform=macOS", timeout: 60
            )
        }
    }

    @Test("Given successful build but missing xctestrun, when build called, then throws xctestrunNotFound")
    func throwsXctestrunNotFoundWhenFileAbsent() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let productsDir = projectDir.appendingPathComponent(".xmr-derived-data/Build/Products")
        try FileManager.default.createDirectory(at: productsDir, withIntermediateDirectories: true)

        let sandbox = Sandbox(rootURL: projectDir)
        let stage = BuildStage(launcher: MockProcessLauncher(exitCode: 0))

        await #expect(throws: BuildError.xctestrunNotFound) {
            try await stage.build(
                sandbox: sandbox,
                scheme: "App",
                destination: "platform=macOS,arch=arm64",
                timeout: 60
            )
        }
    }

    @Test("Given successful SPM build, when buildSPM called, then returns artifact with nil xctestrunURL and plist")
    func spmBuildReturnsArtifactWithNilXctestrunAndPlist() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        try makeTestBundles(named: ["MyLibTests"], in: projectDir)

        let sandbox = Sandbox(rootURL: projectDir)
        let stage = BuildStage(launcher: MockProcessLauncher(exitCode: 0, producesTestBundle: false))

        let artifact = try await stage.buildSPM(sandbox: sandbox, timeout: 60)

        #expect(artifact.derivedDataPath == projectDir.appendingPathComponent(".build").path)
        #expect(artifact.xctestrunURL == nil)
        #expect(artifact.plist == nil)
    }

    @Test("Given built test bundles, when buildSPM called, then their sandbox-relative paths are returned")
    func spmBuildReturnsTestBundlePaths() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        try makeTestBundles(named: ["BTests", "ATests"], in: projectDir)

        let sandbox = Sandbox(rootURL: projectDir)
        let stage = BuildStage(launcher: MockProcessLauncher(exitCode: 0, producesTestBundle: false))

        let artifact = try await stage.buildSPM(sandbox: sandbox, timeout: 60)

        #expect(
            artifact.testBundlePaths == [
                ".build/debug/ATests.xctest", ".build/debug/BTests.xctest",
            ]
        )
    }

    @Test("Given SwiftPM's symlinked products directory, when buildSPM called, then the bundle behind it is found")
    func spmBuildFindsBundlesBehindProductsSymlink() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let realProductsDir = projectDir.appendingPathComponent(".build/arm64-apple-macosx/debug")
        try FileManager.default.createDirectory(at: realProductsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: realProductsDir.appendingPathComponent("MyLibTests.xctest"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            atPath: projectDir.appendingPathComponent(".build/debug").path,
            withDestinationPath: "arm64-apple-macosx/debug"
        )

        let sandbox = Sandbox(rootURL: projectDir)
        let stage = BuildStage(launcher: MockProcessLauncher(exitCode: 0, producesTestBundle: false))

        let artifact = try await stage.buildSPM(sandbox: sandbox, timeout: 60)

        #expect(artifact.testBundlePaths == [".build/debug/MyLibTests.xctest"])
    }

    @Test("Given SPM build producing no test bundle, when buildSPM called, then throws testBundleNotFound")
    func spmBuildWithoutTestBundleThrows() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let sandbox = Sandbox(rootURL: projectDir)
        let stage = BuildStage(launcher: MockProcessLauncher(exitCode: 0, producesTestBundle: false))

        await #expect(throws: BuildError.testBundleNotFound) {
            try await stage.buildSPM(sandbox: sandbox, timeout: 60)
        }
    }

    @Test("Given SPM build failure, when buildSPM called, then throws compilationFailed")
    func spmBuildFailureThrowsCompilationFailed() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let sandbox = Sandbox(rootURL: projectDir)
        let stage = BuildStage(launcher: MockProcessLauncher(exitCode: 1))

        await #expect {
            try await stage.buildSPM(sandbox: sandbox, timeout: 60)
        } throws: { error in
            guard case BuildError.compilationFailed = error else { return false }
            return true
        }
    }

}

private func makeTestBundles(named names: [String], in sandboxRoot: URL) throws {
    let productsDir = sandboxRoot.appendingPathComponent(".build/debug")
    try FileManager.default.createDirectory(at: productsDir, withIntermediateDirectories: true)

    for name in names {
        try FileManager.default.createDirectory(
            at: productsDir.appendingPathComponent("\(name).xctest"),
            withIntermediateDirectories: true
        )
    }
}
