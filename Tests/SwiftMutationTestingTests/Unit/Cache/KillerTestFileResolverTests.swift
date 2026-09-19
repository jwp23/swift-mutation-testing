import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("KillerTestFileResolver")
struct KillerTestFileResolverTests {
    @Test("Given XCTest class name, when resolved, then returns file matching class name")
    func resolvesXCTestClassName() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        let filePath = testsDir.appendingPathComponent("CalculatorTests.swift").path
        try "import XCTest".write(toFile: filePath, atomically: true, encoding: .utf8)

        let resolver = KillerTestFileResolver(testFilePaths: [filePath])

        let result = resolver.resolve(testName: "CalculatorTests.testAddition")

        #expect(result == filePath)
    }

    @Test("Given XCTest three-part name, when resolved, then returns file matching middle component")
    func resolvesXCTestThreePartName() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        let filePath = testsDir.appendingPathComponent("CalculatorTests.swift").path
        try "import XCTest".write(toFile: filePath, atomically: true, encoding: .utf8)

        let resolver = KillerTestFileResolver(testFilePaths: [filePath])

        let result = resolver.resolve(testName: "MyModule.CalculatorTests.testAddition")

        #expect(result == filePath)
    }

    @Test("Given Swift Testing function name, when resolved, then returns file containing function")
    func resolvesSwiftTestingFunctionName() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        let filePath = testsDir.appendingPathComponent("MathTests.swift").path
        try "func testAddition() { }".write(toFile: filePath, atomically: true, encoding: .utf8)

        let resolver = KillerTestFileResolver(testFilePaths: [filePath])

        let result = resolver.resolve(testName: "MyModule/MathTests/testAddition")

        #expect(result == filePath)
    }

    @Test("Given a mock whose content matches the test name, when resolved, then the real test file is returned")
    func ignoresMockMatchingTestNameTextually() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let mocksDir = dir.appendingPathComponent("Tests/Mocks")
        try FileManager.default.createDirectory(at: mocksDir, withIntermediateDirectories: true)
        let mockPath = mocksDir.appendingPathComponent("NetworkMock.swift").path
        try "func fetchData() { }".write(toFile: mockPath, atomically: true, encoding: .utf8)

        let testsDir = dir.appendingPathComponent("Tests")
        let testPath = testsDir.appendingPathComponent("NetworkTests.swift").path
        try "@Test func fetchData() { }".write(toFile: testPath, atomically: true, encoding: .utf8)

        let resolver = KillerTestFileResolver(testFilePaths: [mockPath, testPath])

        let result = resolver.resolve(testName: "MyModule/NetworkTests/fetchData")

        #expect(result == testPath)
    }

    @Test("Given a mock ineligible as a killer, when classified for hashing, then it is still a test file")
    func mockRemainsATestFileForHashing() {
        #expect(TestFileConvention.isTestFile(path: "/project/Tests/Mocks/NetworkMock.swift"))
        #expect(!TestFileConvention.declaresTests(path: "/project/Tests/Mocks/NetworkMock.swift"))
    }

    @Test("Given a shared helper in a support directory, when classified, then it declares no tests")
    func supportDirectoryHelperDeclaresNoTests() {
        #expect(!TestFileConvention.declaresTests(path: "/project/Tests/TestSupport/FileHelpers.swift"))
        #expect(TestFileConvention.declaresTests(path: "/project/Tests/AppTests/LoginTests.swift"))
        #expect(TestFileConvention.declaresTests(path: "/project/Tests/AppTests/LoginSpec.swift"))
    }

    @Test("Given unknown test name, when resolved, then returns nil")
    func returnsNilForUnknownTestName() {
        let resolver = KillerTestFileResolver(testFilePaths: ["/some/path/FooTests.swift"])

        let result = resolver.resolve(testName: "UnknownTests.testSomething")

        #expect(result == nil)
    }

    @Test("Given empty test file paths, when resolved, then returns nil")
    func returnsNilWhenNoTestFiles() {
        let resolver = KillerTestFileResolver(testFilePaths: [])

        let result = resolver.resolve(testName: "SomeTests.testMethod")

        #expect(result == nil)
    }
}
