import Foundation

enum BuildError: Error, Equatable, LocalizedError {
    case compilationFailed(output: String)
    case xctestrunNotFound
    case testBundleNotFound
    case testTargetUnscopable(testTarget: String)
    case testTargetIncompatibleWithSwiftTesting(testTarget: String)

    var errorDescription: String? {
        switch self {
        case .compilationFailed(let output):
            var message = "Build failed. The schematized source could not be compiled."
            if !output.isEmpty { message = output + "\n" + message }
            return message

        case .xctestrunNotFound:
            return "xctestrun file not found after build."

        case .testBundleNotFound:
            return "No .xctest bundle found after build."

        case .testTargetUnscopable(let testTarget):
            return
                "--target \(testTarget) matched no test bundle in this project's build output "
                + "— this SwiftPM project appears to merge all test targets into one bundle, which this "
                + "flag cannot scope to; remove --target or restructure the project's test targets."

        case .testTargetIncompatibleWithSwiftTesting(let testTarget):
            return
                "--target \(testTarget) selects a class or method, but this project's tests are "
                + "Swift Testing — there is no XCTest selector that can scope to specific Swift Testing "
                + "tests, so this would silently run none of them; use a bundle-level --target "
                + "(no class/method suffix) instead."
        }
    }

    static func == (lhs: BuildError, rhs: BuildError) -> Bool {
        switch (lhs, rhs) {
        case (.compilationFailed, .compilationFailed): return true
        case (.xctestrunNotFound, .xctestrunNotFound): return true
        case (.testBundleNotFound, .testBundleNotFound): return true
        case (.testTargetUnscopable, .testTargetUnscopable): return true
        case (.testTargetIncompatibleWithSwiftTesting, .testTargetIncompatibleWithSwiftTesting): return true
        default: return false
        }
    }
}
