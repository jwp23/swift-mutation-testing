import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("OutputLineBuffer")
struct OutputLineBufferTests {

    @Test("Given a chunk holding whole lines, when appended, then every line is reported")
    func wholeLinesAreReported() {
        let buffer = OutputLineBuffer()

        #expect(buffer.append(Data("one\ntwo\n".utf8)) == ["one", "two"])
    }

    @Test("Given a chunk ending mid-line, when appended, then the partial line waits for the rest")
    func partialLineWaitsForTheRestOfTheChunk() {
        let buffer = OutputLineBuffer()

        #expect(buffer.append(Data("one\ntw".utf8)) == ["one"])
        #expect(buffer.append(Data("o\nthree\n".utf8)) == ["two", "three"])
    }

    @Test("Given a multi-byte character split across chunks, when appended, then the line decodes intact")
    func multiByteCharacterSplitAcrossChunksDecodesIntact() {
        let buffer = OutputLineBuffer()
        let bytes = Array(Data("passed \u{2713}\n".utf8))

        #expect(buffer.append(Data(bytes[0 ..< 8])).isEmpty)
        #expect(buffer.append(Data(bytes[8...])) == ["passed \u{2713}"])
    }

    @Test("Given several appended chunks, when output read, then it holds everything appended")
    func outputHoldsEverythingAppended() {
        let buffer = OutputLineBuffer()

        _ = buffer.append(Data("one\ntw".utf8))
        _ = buffer.append(Data("o\nunfinished".utf8))

        #expect(buffer.output == "one\ntwo\nunfinished")
    }
}
