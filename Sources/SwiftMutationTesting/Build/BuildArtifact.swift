import Foundation

struct BuildArtifact: Sendable {
    let derivedDataPath: String
    let xctestrunURL: URL?
    let plist: XCTestRunPlist?

    /// Test bundles produced by the one SPM build, as paths relative to the sandbox root, so a
    /// worker can resolve them inside its own copy of that sandbox. Empty for Xcode builds,
    /// which select their tests through the xctestrun plist instead.
    let testBundlePaths: [String]
}
