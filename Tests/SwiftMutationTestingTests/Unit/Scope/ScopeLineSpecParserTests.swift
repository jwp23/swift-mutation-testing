import Testing

@testable import SwiftMutationTesting

@Suite("ScopeLineSpecParser")
struct ScopeLineSpecParserTests {
    private let parser = ScopeLineSpecParser()

    @Test("Given a path:start-end spec, when parsed, then those lines are in scope")
    func parsesPathAndRange() throws {
        let scope = try parser.parse(["Sources/Foo.swift:10-20"])

        #expect(scope.contains(filePath: "/p/Sources/Foo.swift", line: 10))
        #expect(scope.contains(filePath: "/p/Sources/Foo.swift", line: 20))
        #expect(!scope.contains(filePath: "/p/Sources/Foo.swift", line: 21))
    }

    @Test("Given two specs for the same path, when parsed, then both ranges are in scope")
    func parsesRepeatedPath() throws {
        let scope = try parser.parse(["Foo.swift:1-2", "Foo.swift:30-31"])

        #expect(scope.contains(filePath: "/p/Foo.swift", line: 2))
        #expect(scope.contains(filePath: "/p/Foo.swift", line: 30))
    }

    @Test("Given no specs, when parsed, then the scope is empty")
    func parsesEmptySpecList() throws {
        #expect(try parser.parse([]).isEmpty)
    }

    @Test("Given a spec without a range, when parsed, then it throws a usage error")
    func rejectsSpecWithoutRange() {
        #expect(throws: UsageError.self) { try parser.parse(["Foo.swift"]) }
    }

    @Test("Given a spec with a non-numeric bound, when parsed, then it throws a usage error")
    func rejectsNonNumericBound() {
        #expect(throws: UsageError.self) { try parser.parse(["Foo.swift:a-3"]) }
    }

    @Test("Given a spec whose range runs backwards, when parsed, then it throws a usage error")
    func rejectsBackwardsRange() {
        #expect(throws: UsageError.self) { try parser.parse(["Foo.swift:9-3"]) }
    }

    @Test("Given a spec starting before the first line, when parsed, then it throws a usage error")
    func rejectsRangeStartingBelowOne() {
        #expect(throws: UsageError.self) { try parser.parse(["Foo.swift:0-3"]) }
    }

    @Test("Given a spec without a path, when parsed, then it throws a usage error")
    func rejectsSpecWithoutPath() {
        #expect(throws: UsageError.self) { try parser.parse([":1-3"]) }
    }

    @Test("Given a spec naming a single line twice over, when parsed, then that line is in scope")
    func parsesSingleLineRange() throws {
        let scope = try parser.parse(["Foo.swift:7-7"])

        #expect(scope.contains(filePath: "/p/Foo.swift", line: 7))
        #expect(!scope.contains(filePath: "/p/Foo.swift", line: 8))
    }
}
