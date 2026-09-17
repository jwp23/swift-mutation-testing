import Foundation

struct BuildStage: Sendable {
    /// Directory SwiftPM links its debug products into, relative to the package root.
    static let spmProductsDirectory = ".build/debug"

    let launcher: any ProcessLaunching

    func build(
        sandbox: Sandbox,
        scheme: String,
        destination: String,
        timeout: Double
    ) async throws -> BuildArtifact {
        let derivedDataURL = sandbox.rootURL.appendingPathComponent(".xmr-derived-data")

        var arguments = [
            "build-for-testing",
            "-scheme", scheme,
            "-destination", destination,
            "-derivedDataPath", derivedDataURL.path,
        ]

        if let workspaceURL = findXcworkspace(in: sandbox.rootURL) {
            arguments += ["-workspace", workspaceURL.path]
        } else if let projectURL = findXcodeproj(in: sandbox.rootURL) {
            arguments += ["-project", projectURL.path]
        }

        let (exitCode, buildOutput) = try await launcher.launchCapturing(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
                arguments: arguments,
                environment: nil,
                additionalEnvironment: [:],
                workingDirectoryURL: sandbox.rootURL,
                timeout: timeout
            )
        )

        guard exitCode == 0 else {
            throw BuildError.compilationFailed(output: buildOutput)
        }

        let productsURL = derivedDataURL.appendingPathComponent("Build/Products")

        guard let xctestrunURL = findXctestrun(in: productsURL) else {
            throw BuildError.xctestrunNotFound
        }

        let data = try Data(contentsOf: xctestrunURL)

        guard let plist = XCTestRunPlist(data) else {
            throw BuildError.xctestrunNotFound
        }

        return BuildArtifact(
            derivedDataPath: derivedDataURL.path,
            xctestrunURL: xctestrunURL,
            plist: plist,
            testBundlePaths: []
        )
    }

    func buildSPM(
        sandbox: Sandbox,
        timeout: Double
    ) async throws -> BuildArtifact {
        let arguments = ["build", "--build-tests"]

        let (exitCode, buildOutput) = try await launcher.launchCapturing(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
                arguments: arguments,
                environment: nil,
                additionalEnvironment: [:],
                workingDirectoryURL: sandbox.rootURL,
                timeout: timeout
            )
        )

        guard exitCode == 0 else { throw BuildError.compilationFailed(output: buildOutput) }

        let testBundlePaths = findTestBundlePaths(in: sandbox)

        guard !testBundlePaths.isEmpty else { throw BuildError.testBundleNotFound }

        return BuildArtifact(
            derivedDataPath: sandbox.rootURL.appendingPathComponent(".build").path,
            xctestrunURL: nil,
            plist: nil,
            testBundlePaths: testBundlePaths
        )
    }

    /// SwiftPM links its products directory to a per-triple one, and enumeration does not follow
    /// that symlink, so the search resolves it first. The paths returned still go through the
    /// symlink, which a replicated sandbox carries along with the directory it points at.
    private func findTestBundlePaths(in sandbox: Sandbox) -> [String] {
        let productsURL = sandbox.rootURL
            .appendingPathComponent(Self.spmProductsDirectory)
            .resolvingSymlinksInPath()
        let items =
            (try? FileManager.default.contentsOfDirectory(
                at: productsURL,
                includingPropertiesForKeys: nil
            )) ?? []

        return
            items
            .filter { $0.pathExtension == "xctest" }
            .map { "\(Self.spmProductsDirectory)/\($0.lastPathComponent)" }
            .sorted()
    }

    private func findXcworkspace(in directory: URL) -> URL? {
        let items =
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )) ?? []
        return items.first { $0.pathExtension == "xcworkspace" }
    }

    private func findXcodeproj(in directory: URL) -> URL? {
        let items =
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )) ?? []
        return items.first { $0.pathExtension == "xcodeproj" }
    }

    private func findXctestrun(in directory: URL) -> URL? {
        let items =
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )) ?? []
        return items.first { $0.pathExtension == "xctestrun" }
    }
}
