import Testing

@testable import SwiftMutationTesting

@Suite("GitDiffParser")
struct GitDiffParserTests {
    private let parser = GitDiffParser()

    @Test("Given a hunk adding lines, when parsed, then those lines are in scope")
    func addedLinesAreInScope() {
        let scope = parser.parse(
            """
            diff --git a/Sources/Foo.swift b/Sources/Foo.swift
            index 1111111..2222222 100644
            --- a/Sources/Foo.swift
            +++ b/Sources/Foo.swift
            @@ -12,0 +13,2 @@ func f() {
            +    let a = 1
            +    let b = 2
            """
        )

        #expect(scope.contains(filePath: "/p/Sources/Foo.swift", line: 13))
        #expect(scope.contains(filePath: "/p/Sources/Foo.swift", line: 14))
        #expect(!scope.contains(filePath: "/p/Sources/Foo.swift", line: 15))
    }

    @Test("Given a hunk header without a count, when parsed, then the single line is in scope")
    func singleChangedLineIsInScope() {
        let scope = parser.parse(
            """
            --- a/Foo.swift
            +++ b/Foo.swift
            @@ -7 +7 @@
            -    let a = 1
            +    let a = 2
            """
        )

        #expect(scope.contains(filePath: "/p/Foo.swift", line: 7))
        #expect(!scope.contains(filePath: "/p/Foo.swift", line: 8))
    }

    @Test("Given a hunk that only deletes lines, when parsed, then nothing is in scope for it")
    func pureDeletionIsNotInScope() {
        let scope = parser.parse(
            """
            --- a/Foo.swift
            +++ b/Foo.swift
            @@ -5,3 +4,0 @@
            -    let a = 1
            """
        )

        #expect(!scope.covers(filePath: "/p/Foo.swift"))
    }

    @Test("Given a diff over several files, when parsed, then each file keeps its own lines")
    func keepsLinesPerFile() {
        let scope = parser.parse(
            """
            --- a/Foo.swift
            +++ b/Foo.swift
            @@ -1 +1 @@
            +let a = 1
            --- a/Bar.swift
            +++ b/Bar.swift
            @@ -9 +9,2 @@
            +let b = 2
            +let c = 3
            """
        )

        #expect(scope.contains(filePath: "/p/Foo.swift", line: 1))
        #expect(!scope.contains(filePath: "/p/Foo.swift", line: 9))
        #expect(scope.contains(filePath: "/p/Bar.swift", line: 10))
    }

    @Test("Given a deleted file, when parsed, then it is in scope whole")
    func deletedFileIsInScopeWhole() {
        let scope = parser.parse(
            """
            --- a/FooTests.swift
            +++ /dev/null
            @@ -1,3 +0,0 @@
            -let a = 1
            """
        )

        #expect(scope.contains(filePath: "/p/FooTests.swift", line: 1))
        #expect(scope.contains(filePath: "/p/FooTests.swift", line: 9_999))
    }

    @Test("Given an added file, when parsed, then the file it replaces nothing of is not in scope")
    func addedFileDoesNotScopeTheAbsentOldSide() {
        let scope = parser.parse(
            """
            --- /dev/null
            +++ b/Foo.swift
            @@ -0,0 +1,2 @@
            +let a = 1
            +let b = 2
            """
        )

        #expect(scope.contains(filePath: "/p/Foo.swift", line: 2))
        #expect(scope.paths == ["Foo.swift"])
    }

    @Test("Given an empty diff, when parsed, then the scope is empty")
    func emptyDiffIsEmptyScope() {
        #expect(parser.parse("").isEmpty)
    }

    @Test("Given a diff written without path prefixes, when parsed, then the path is still read")
    func readsPathWithoutPrefix() {
        let scope = parser.parse(
            """
            --- Foo.swift
            +++ Foo.swift
            @@ -1 +1 @@
            +let a = 1
            """
        )

        #expect(scope.contains(filePath: "/p/Foo.swift", line: 1))
    }

    @Test("Given a diff with a C-quoted non-ASCII path, when parsed, then the decoded path is in scope")
    func decodesCQuotedNonASCIIPath() {
        let scope = parser.parse(
            """
            --- "a/Sources/F\\303\\257le.swift"
            +++ "b/Sources/F\\303\\257le.swift"
            @@ -1 +1 @@
            +let a = 1
            """
        )

        #expect(scope.contains(filePath: "/p/Sources/Fïle.swift", line: 1))
    }

    @Test("Given a diff with a C-quoted path containing an escaped quote, when parsed, then it decodes")
    func decodesCQuotedPathWithEscapedQuote() {
        let scope = parser.parse(
            """
            --- "a/Sources/\\"Foo\\".swift"
            +++ "b/Sources/\\"Foo\\".swift"
            @@ -1 +1 @@
            +let a = 1
            """
        )

        #expect(scope.contains(filePath: "/p/Sources/\"Foo\".swift", line: 1))
    }
}
