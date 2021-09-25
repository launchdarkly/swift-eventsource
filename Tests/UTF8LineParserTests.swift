import XCTest
@testable import LDSwiftEventSource

final class UTF8LineParserTests: XCTestCase {
    var parser = UTF8LineParser()

    override func setUp() {
        super.setUp()
        parser = UTF8LineParser()
    }

    func testNoData() {
        XCTAssertNil(parser.closeAndReset())
    }

    func testEmptyData() {
        XCTAssertEqual(parser.append(Data()), [])
        XCTAssertNil(parser.closeAndReset())
    }

    func testEmptyCrLine() {
        XCTAssertEqual(parser.append(Data("\r".utf8)), [])
        XCTAssertEqual(parser.closeAndReset(), "")
    }

    /// Called after some tests to validate that `closeAndReset` completely resets the parser
    func assertCompletelyReset() {
        XCTAssertEqual(parser.append(Data("abc\r".utf8)), [])
        XCTAssertEqual(parser.closeAndReset(), "abc")
    }

    func testBasicLineUnterminated() {
        let line = "test string"
        XCTAssertEqual(parser.append(line.data(using: .utf8)!), [])
        XCTAssertNil(parser.closeAndReset())
        assertCompletelyReset()
    }

    func testBasicLineCr() {
        let line = "test string"
        let data = Data((line + "\r").utf8)
        XCTAssertEqual(parser.append(data), [])
        XCTAssertEqual(parser.closeAndReset(), line)
        assertCompletelyReset()
    }

    func testBasicLineLf() {
        let line = "test string"
        let data = Data((line + "\n").utf8)
        XCTAssertEqual(parser.append(data), [line])
        XCTAssertNil(parser.closeAndReset())
        assertCompletelyReset()
    }

    func testBasicLineCrLf() {
        let line = "test string"
        let data = Data((line + "\r\n").utf8)
        XCTAssertEqual(parser.append(data), [line])
        XCTAssertNil(parser.closeAndReset())
        assertCompletelyReset()
    }

    func testBasicSplit() {
        XCTAssertEqual(parser.append(Data("test ".utf8)), [])
        XCTAssertEqual(parser.append(Data("string\r".utf8)), [])
        XCTAssertEqual(parser.closeAndReset(), "test string")
    }

    func testUnicodeString() {
        let line = "¯\\_(ツ)_/¯0️⃣🇺🇸Z̮̞̠͙͔ͅḀ̗̞͈̻̗Ḷ͙͎̯̹̞͓G̻O̭̗̮𝓯𝓸𝔁"
        XCTAssertEqual(parser.append(Data((line + "\n").utf8)), [line])
        XCTAssertNil(parser.closeAndReset())
    }

    func testInvalidCharacterReplaced() {
        let line = "test✨string"
        var data = Data((line + "\n").utf8)
        // Remove 3rd and last byte of "✨"
        data.remove(at: 6)
        let expected = "test�string"
        XCTAssertEqual(parser.append(data), [expected])
        XCTAssertNil(parser.closeAndReset())
    }

    // Simulates a multi-code-unit code point being split across received chunks from the network.
    func testCodePointSplitNotReplaced() {
        let line = "test✨string"
        let data = Data((line + "\r").utf8)
        let data1 = data.subdata(in: 0..<6)
        let data2 = data.subdata(in: 6..<14)
        XCTAssertEqual(parser.append(data1), [])
        XCTAssertEqual(parser.append(data2), [])
        XCTAssertEqual(parser.closeAndReset(), line)
    }

    // Simulates the stream dropping part way through a multi-code-unit code point.
    func testResetAfterPartialInvalid() {
        var data = Data("test✨".utf8)
        data.remove(at: 6)
        XCTAssertEqual(parser.append(data), [])
        XCTAssertNil(parser.closeAndReset())
        assertCompletelyReset()
    }

    func testInvalidCharacterReplacedOnNextLineAfterCr() {
        let line = "test\r✨string\r"
        var data = Data(line.utf8)
        // Remove 3rd and last byte of "✨"
        data.remove(at: 7)
        XCTAssertEqual(parser.append(data), ["test"])
        XCTAssertEqual(parser.closeAndReset(), "�string")
    }

    func testMultiLineDataMixedLineEnding() {
        let line = "test1\rtest2\ntest3\r\ntest4\r\rtest5\n\n"
        let data = Data(line.utf8)
        let expected = ["test1", "test2", "test3", "test4", "", "test5", ""]
        XCTAssertEqual(parser.append(data), expected)
        XCTAssertNil(parser.closeAndReset())
    }
}
