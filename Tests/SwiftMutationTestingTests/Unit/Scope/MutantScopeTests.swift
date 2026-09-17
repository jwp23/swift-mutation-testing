import Testing

@testable import SwiftMutationTesting

@Suite("MutantScope")
struct MutantScopeTests {
    @Test("Given a line inside a scoped range, when asked, then the mutant is in scope")
    func lineInsideRangeIsInScope() {
        let scope = MutantScope(lineRangesByPath: ["Sources/Foo.swift": [10 ... 20]])

        #expect(scope.contains(filePath: "/p/Sources/Foo.swift", line: 15))
    }

    @Test("Given a line outside every scoped range, when asked, then the mutant is out of scope")
    func lineOutsideRangesIsOutOfScope() {
        let scope = MutantScope(lineRangesByPath: ["Sources/Foo.swift": [10 ... 20]])

        #expect(!scope.contains(filePath: "/p/Sources/Foo.swift", line: 21))
    }

    @Test("Given several ranges for one path, when asked, then a line in any of them is in scope")
    func lineInAnyRangeIsInScope() {
        let scope = MutantScope(lineRangesByPath: ["Foo.swift": [1 ... 2, 40 ... 41]])

        #expect(scope.contains(filePath: "/p/Foo.swift", line: 40))
        #expect(!scope.contains(filePath: "/p/Foo.swift", line: 3))
    }

    @Test("Given a scoped path, when a different file has the same line, then it is out of scope")
    func otherFileIsOutOfScope() {
        let scope = MutantScope(lineRangesByPath: ["Sources/Foo.swift": [10 ... 20]])

        #expect(!scope.contains(filePath: "/p/Sources/Bar.swift", line: 15))
    }

    @Test("Given a path that is a partial name of the file, when asked, then it does not match")
    func partialNameDoesNotMatch() {
        let scope = MutantScope(lineRangesByPath: ["oo.swift": [1 ... 5]])

        #expect(!scope.contains(filePath: "/p/Sources/Foo.swift", line: 3))
    }

    @Test("Given an absolute scoped path, when the mutant path equals it, then it is in scope")
    func absolutePathMatchesExactly() {
        let scope = MutantScope(lineRangesByPath: ["/p/Sources/Foo.swift": [1 ... 5]])

        #expect(scope.contains(filePath: "/p/Sources/Foo.swift", line: 3))
    }

    @Test("Given a whole-file range, when asked for any line, then it is in scope")
    func wholeFileCoversEveryLine() {
        let scope = MutantScope(lineRangesByPath: ["Foo.swift": [MutantScope.everyLine]])

        #expect(scope.contains(filePath: "/p/Foo.swift", line: 1))
        #expect(scope.contains(filePath: "/p/Foo.swift", line: 9_999))
    }

    @Test("Given a scoped path, when asked whether the file is covered, then only that file is")
    func coversOnlyScopedFiles() {
        let scope = MutantScope(lineRangesByPath: ["Sources/Foo.swift": [10 ... 20]])

        #expect(scope.covers(filePath: "/p/Sources/Foo.swift"))
        #expect(!scope.covers(filePath: "/p/Sources/Bar.swift"))
    }

    @Test("Given two scopes, when united, then the result covers the lines of both")
    func unionCoversBothScopes() {
        let scope = MutantScope(lineRangesByPath: ["Foo.swift": [1 ... 2]])
            .union(MutantScope(lineRangesByPath: ["Foo.swift": [8 ... 9], "Bar.swift": [3 ... 3]]))

        #expect(scope.contains(filePath: "/p/Foo.swift", line: 1))
        #expect(scope.contains(filePath: "/p/Foo.swift", line: 8))
        #expect(scope.contains(filePath: "/p/Bar.swift", line: 3))
    }

    @Test("Given an empty scope, when asked, then nothing is in scope and it reports itself empty")
    func emptyScopeContainsNothing() {
        let scope = MutantScope(lineRangesByPath: [:])

        #expect(scope.isEmpty)
        #expect(!scope.contains(filePath: "/p/Foo.swift", line: 1))
    }

    @Test("Given a scope, when described, then it names every path and the lines it covers there")
    func describesItsPathsAndLines() {
        let scope = MutantScope(
            lineRangesByPath: [
                "Sources/Foo.swift": [10 ... 20, 30 ... 30],
                "Sources/Bar.swift": [MutantScope.everyLine],
            ]
        )

        #expect(scope.description == "Sources/Bar.swift:all, Sources/Foo.swift:10-20,30-30")
    }

    @Test("Given an empty scope, when described, then it says it covers nothing")
    func emptyScopeDescribesItself() {
        #expect(MutantScope(lineRangesByPath: [:]).description == "nothing")
    }

    @Test("Given a scope, when asked for its paths, then it lists the paths it was built from")
    func listsItsPaths() {
        let scope = MutantScope(lineRangesByPath: ["Foo.swift": [1 ... 2], "Bar.swift": [3 ... 4]])

        #expect(scope.paths.sorted() == ["Bar.swift", "Foo.swift"])
    }

    @Test("Given a path beginning with ./, when constructed, then it matches the same as without it")
    func leadingDotSlashIsNormalized() {
        let scope = MutantScope(lineRangesByPath: ["./Sources/Foo.swift": [10 ... 20]])

        #expect(scope.contains(filePath: "/p/Sources/Foo.swift", line: 15))
        #expect(scope.paths == ["Sources/Foo.swift"])
    }

    @Test("Given a path with repeated separators, when constructed, then it matches the collapsed path")
    func repeatedSeparatorsAreNormalized() {
        let scope = MutantScope(lineRangesByPath: ["Sources//Foo.swift": [10 ... 20]])

        #expect(scope.contains(filePath: "/p/Sources/Foo.swift", line: 15))
    }
}
