import Foundation

@testable import SwiftMutationTesting

/// Writes the `.xctest` bundle a real `swift build --build-tests` leaves in the sandbox. Mocked
/// launchers call this so stages that locate built products find one even though the build that
/// would have produced it never ran.
func writeMockedTestBundle(for request: ProcessRequest) {
    guard request.arguments.first == "build" else { return }

    let bundleURL = request.workingDirectoryURL
        .appendingPathComponent(BuildStage.spmProductsDirectory)
        .appendingPathComponent("FixtureTests.xctest")

    try? FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
}
