import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("PathRelativizer")
struct PathRelativizerTests {

    @Test("Given a path under root, when relativePath called, then the root prefix is stripped")
    func relativePathStripsRootPrefix() throws {
        let root = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(root) }

        let filePath = root.appendingPathComponent("Tests/FooTests.swift").path

        let result = PathRelativizer.relativePath(for: filePath, relativeTo: root.path)

        #expect(result == "Tests/FooTests.swift")
    }

    @Test(
        "Given a sibling directory sharing root's name as a prefix, when relativePath called, then the path is returned unchanged"
    )
    func relativePathDoesNotTreatSiblingAsDescendant() throws {
        let root = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(root) }

        // A sibling whose name has `root`'s path as a plain string prefix, e.g. root
        // "/tmp/xyz-project" and sibling "/tmp/xyz-project-copy" — never actually under root.
        let siblingRoot = URL(fileURLWithPath: root.path + "-copy")
        try FileManager.default.createDirectory(at: siblingRoot, withIntermediateDirectories: true)
        defer { FileHelpers.cleanup(siblingRoot) }

        let siblingFilePath = siblingRoot.appendingPathComponent("Tests/FooTests.swift").path

        let result = PathRelativizer.relativePath(for: siblingFilePath, relativeTo: root.path)

        #expect(result == siblingFilePath)
    }

    @Test("Given a path exactly equal to root, when relativePath called, then an empty relative path is returned")
    func relativePathHandlesExactRootMatch() throws {
        let root = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(root) }

        let result = PathRelativizer.relativePath(for: root.path, relativeTo: root.path)

        #expect(result == "")
    }
}
