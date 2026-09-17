import Foundation

/// Bundles a run's tests execute in, and the XCTest selection applied inside them. A configured
/// test target names the bundle with its first path component; anything after that is an XCTest
/// selector (`Class` or `Class/method`).
struct BundleSelection: Sendable {
    let paths: [String]
    let xctestSelection: String?

    /// What a configured test target selects in this build's output.
    ///
    /// A target naming no bundle — what a toolchain that merges every test target into one bundle
    /// produces — cannot be scoped to at all, and fails the run rather than silently widening it
    /// to every bundle: broader execution can change a mutant's kill/survive verdict, not just its
    /// runtime. Xcode builds select their tests through an xctestrun plist instead of a bundle
    /// list, so a target of theirs is never resolved against one.
    static func resolve(
        artifact: BuildArtifact, testTarget: String?, testingFramework: TestingFramework
    ) throws -> BundleSelection {
        let allPaths = artifact.testBundlePaths

        guard let testTarget else {
            return BundleSelection(paths: allPaths, xctestSelection: nil)
        }

        var components = testTarget.components(separatedBy: "/")
        let targetName = components.removeFirst()
        let matching = allPaths.filter {
            URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent == targetName
        }

        if matching.isEmpty, artifact.plist == nil {
            throw BuildError.testTargetUnscopable(testTarget: testTarget)
        }

        let xctestSelection = components.isEmpty ? nil : components.joined(separator: "/")

        // An XCTest selector built here cannot also scope Swift Testing tests in the same
        // bundle — running one would silently run zero of the other, which can turn a real
        // mutant kill into a false Survived. Fail rather than silently under-running the suite.
        // SPM only: Xcode builds scope through `-only-testing` instead (see `launch(...)`),
        // which handles a Swift Testing class/method target correctly.
        if xctestSelection != nil, artifact.plist == nil, testingFramework == .swiftTesting {
            throw BuildError.testTargetIncompatibleWithSwiftTesting(testTarget: testTarget)
        }

        return BundleSelection(
            paths: matching.isEmpty ? allPaths : matching,
            xctestSelection: xctestSelection
        )
    }
}
