import Foundation

@testable import SwiftMutationTesting

struct MockProcessLauncher: ProcessLaunching {

    init(
        exitCode: Int32,
        output: String = "",
        responses: [String: (exitCode: Int32, output: String)] = [:],
        throwsOnCapture: Bool = false,
        producesTestBundle: Bool = true,
        testBundleName: String = "FixtureTests"
    ) {
        self.exitCode = exitCode
        self.output = output
        self.responses = responses
        self.throwsOnCapture = throwsOnCapture
        self.producesTestBundle = producesTestBundle
        self.testBundleName = testBundleName
    }

    let exitCode: Int32
    let output: String
    let responses: [String: (exitCode: Int32, output: String)]
    let throwsOnCapture: Bool

    /// Whether a mocked SPM build leaves a test bundle behind. Tests that assert on which bundles
    /// a build produced turn it off and write the bundles they want themselves.
    let producesTestBundle: Bool

    /// Name of the bundle a mocked build leaves behind, for tests that need it to match a
    /// configured `--target`.
    let testBundleName: String

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        exitCode
    }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        if producesTestBundle { writeMockedTestBundle(for: request, named: testBundleName) }

        if throwsOnCapture { throw CocoaError(.fileReadNoSuchFile) }
        let key = request.executableURL.lastPathComponent
        return responses[key] ?? (exitCode: exitCode, output: output)
    }

}
