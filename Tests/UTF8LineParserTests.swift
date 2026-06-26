import Foundation
import Testing
@testable import LDSwiftEventSource

@Suite("UTF8LineParser")
final class UTF8LineParserTests {
    private let parser = UTF8LineParser()

    deinit {
        // Validate that `closeAndReset` completely resets the parser
        parser.closeAndReset()
        #expect(parser.append(Data("\n".utf8)) == [""])
    }

    // The reset invariant for a fresh, never-appended parser is checked in deinit.
    @Test func noData() { }

    @Test func emptyData() {
        #expect(parser.append(Data()) == [])
    }

    @Test func emptyCrLine() {
        #expect(parser.append(Data("\r".utf8)) == [""])
    }

    @Test func basicLineUnterminated() {
        let line = "test string"
        #expect(parser.append(Data(line.utf8)) == [])
    }

    @Test func basicLineCr() {
        let line = "test string"
        let data = Data((line + "\r").utf8)
        #expect(parser.append(data) == [line])
    }

    @Test func basicLineLf() {
        let line = "test string"
        let data = Data((line + "\n").utf8)
        #expect(parser.append(data) == [line])
    }

    @Test func basicLineCrLf() {
        let line = "test string"
        let data = Data((line + "\r\n").utf8)
        #expect(parser.append(data) == [line])
    }

    @Test func basicSplit() {
        #expect(parser.append(Data("test ".utf8)) == [])
        #expect(parser.append(Data("string\r".utf8)) == ["test string"])
    }

    @Test func unicodeString() {
        let line = "¯\\_(ツ)_/¯0️⃣🇺🇸Z̮̞̠͙͔ͅḀ̗̞͈̻̗Ḷ͙͎̯̹̞͓G̻O̭̗̮𝓯𝓸𝔁"
        #expect(parser.append(Data((line + "\n").utf8)) == [line])
    }

    @Test func nullCodePoint() {
        let line = "\u{0000}"
        #expect(parser.append(Data((line + "\n").utf8)) == [line])
    }

    @Test func invalidCharacterReplaced() {
        let line = "test✨string"
        var data = Data((line + "\n").utf8)
        // Remove 3rd and last byte of "✨"
        data.remove(at: 6)
        let expected = "test�string"
        #expect(parser.append(data) == [expected])
    }

    // Simulates a multi-code-unit code point being split across received chunks from the network.
    @Test func codePointSplitNotReplaced() {
        let line = "test✨string"
        let data = Data((line + "\r").utf8)
        let data1 = data.subdata(in: 0..<6)
        let data2 = data.subdata(in: 6..<14)
        #expect(parser.append(data1) == [])
        #expect(parser.append(data2) == [line])
    }

    // Simulates the stream dropping part way through a multi-code-unit code point.
    @Test func resetAfterPartialInvalid() {
        var data = Data("test✨".utf8)
        data.remove(at: 6)
        #expect(parser.append(data) == [])
    }

    @Test func invalidCharacterReplacedOnNextLineAfterCr() {
        let line = "test\r✨string\r"
        var data = Data(line.utf8)
        // Remove 3rd and last byte of "✨"
        data.remove(at: 7)
        #expect(parser.append(data) == ["test", "�string"])
    }

    @Test func multiLineDataMixedLineEnding() {
        let line = "test1\rtest2\ntest3\r\ntest4\r\rtest5\n\n"
        let data = Data(line.utf8)
        let expected = ["test1", "test2", "test3", "test4", "", "test5", ""]
        #expect(parser.append(data) == expected)
    }
}
