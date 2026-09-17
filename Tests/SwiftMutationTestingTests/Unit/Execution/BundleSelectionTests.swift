import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("BundleSelection")
struct BundleSelectionTests {
    @Test(
        "Given a class-level test target and a Swift Testing project, when resolving, then the run fails rather than silently skipping Swift Testing tests"
    )
    func classLevelTargetOnSwiftTestingProjectFails() throws {
        let artifact = BuildArtifact(
            derivedDataPath: "", xctestrunURL: nil, plist: nil,
            testBundlePaths: [".build/debug/BTests.xctest"]
        )

        #expect(throws: BuildError.testTargetIncompatibleWithSwiftTesting(testTarget: "BTests/SomeSuite")) {
            try BundleSelection.resolve(
                artifact: artifact, testTarget: "BTests/SomeSuite", testingFramework: .swiftTesting
            )
        }
    }

    @Test(
        "Given a bundle-level-only test target and a Swift Testing project, when resolving, then it succeeds"
    )
    func bundleLevelTargetOnSwiftTestingProjectSucceeds() throws {
        let artifact = BuildArtifact(
            derivedDataPath: "", xctestrunURL: nil, plist: nil,
            testBundlePaths: [".build/debug/BTests.xctest"]
        )

        let selection = try BundleSelection.resolve(
            artifact: artifact, testTarget: "BTests", testingFramework: .swiftTesting
        )

        #expect(selection.paths == [".build/debug/BTests.xctest"])
        #expect(selection.xctestSelection == nil)
    }

    @Test(
        "Given a class-level test target and an XCTest project, when resolving, then it succeeds"
    )
    func classLevelTargetOnXCTestProjectSucceeds() throws {
        let artifact = BuildArtifact(
            derivedDataPath: "", xctestrunURL: nil, plist: nil,
            testBundlePaths: [".build/debug/BTests.xctest"]
        )

        let selection = try BundleSelection.resolve(
            artifact: artifact, testTarget: "BTests/SomeSuite", testingFramework: .xctest
        )

        #expect(selection.paths == [".build/debug/BTests.xctest"])
        #expect(selection.xctestSelection == "SomeSuite")
    }

    @Test(
        "Given a class-level test target and an Xcode Swift Testing project, when resolving, then it succeeds because Xcode scopes through -only-testing instead"
    )
    func classLevelTargetOnXcodeSwiftTestingProjectSucceeds() throws {
        let artifact = BuildArtifact(
            derivedDataPath: "", xctestrunURL: nil, plist: makePlist(),
            testBundlePaths: []
        )

        let selection = try BundleSelection.resolve(
            artifact: artifact, testTarget: "BTests/SomeSuite", testingFramework: .swiftTesting
        )

        #expect(selection.xctestSelection == "SomeSuite")
    }
}

private func makePlist() -> XCTestRunPlist {
    let plistDict: [String: Any] = ["MyTarget": ["EnvironmentVariables": [String: String]()]]
    let data = try! PropertyListSerialization.data(
        fromPropertyList: plistDict, format: .xml, options: 0
    )
    return XCTestRunPlist(data)!
}
