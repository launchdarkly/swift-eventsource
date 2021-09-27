import XCTest
@testable import LDSwiftEventSource

final class UTF8LineParserTests: XCTestCase {
    var parser = UTF8LineParser()

    override func setUp() {
        super.setUp()
        parser = UTF8LineParser()
    }

    override func tearDown() {
        super.tearDown()
        // Validate that `closeAndReset` completely resets the parser
        parser.closeAndReset()
        XCTAssertEqual(parser.append(Data("\n".utf8)), [""])
    }

    // swiftlint:disable:next empty_xctest_method - Only runs test in tearDown
    func testNoData() { }

    func testEmptyData() {
        XCTAssertEqual(parser.append(Data()), [])
    }

    func testEmptyCrLine() {
        XCTAssertEqual(parser.append(Data("\r".utf8)), [""])
    }

    func testBasicLineUnterminated() {
        let line = "test string"
        XCTAssertEqual(parser.append(Data(line.utf8)), [])
    }

    func testBasicLineCr() {
        let line = "test string"
        let data = Data((line + "\r").utf8)
        XCTAssertEqual(parser.append(data), [line])
    }

    func testBasicLineLf() {
        let line = "test string"
        let data = Data((line + "\n").utf8)
        XCTAssertEqual(parser.append(data), [line])
    }

    func testBasicLineCrLf() {
        let line = "test string"
        let data = Data((line + "\r\n").utf8)
        XCTAssertEqual(parser.append(data), [line])
    }

    func testBasicSplit() {
        XCTAssertEqual(parser.append(Data("test ".utf8)), [])
        XCTAssertEqual(parser.append(Data("string\r".utf8)), ["test string"])
    }

    func testUnicodeString() {
        let line = "¯\\_(ツ)_/¯0️⃣🇺🇸Z̮̞̠͙͔ͅḀ̗̞͈̻̗Ḷ͙͎̯̹̞͓G̻O̭̗̮𝓯𝓸𝔁"
        XCTAssertEqual(parser.append(Data((line + "\n").utf8)), [line])
    }

    func testNullCodePoint() {
        let line = "\u{0000}"
        XCTAssertEqual(parser.append(Data((line + "\n").utf8)), [line])
    }

    func testInvalidCharacterReplaced() {
        let line = "test✨string"
        var data = Data((line + "\n").utf8)
        // Remove 3rd and last byte of "✨"
        data.remove(at: 6)
        let expected = "test�string"
        XCTAssertEqual(parser.append(data), [expected])
    }

    // Simulates a multi-code-unit code point being split across received chunks from the network.
    func testCodePointSplitNotReplaced() {
        let line = "test✨string"
        let data = Data((line + "\r").utf8)
        let data1 = data.subdata(in: 0..<6)
        let data2 = data.subdata(in: 6..<14)
        XCTAssertEqual(parser.append(data1), [])
        XCTAssertEqual(parser.append(data2), [line])
    }

    // Simulates the stream dropping part way through a multi-code-unit code point.
    func testResetAfterPartialInvalid() {
        var data = Data("test✨".utf8)
        data.remove(at: 6)
        XCTAssertEqual(parser.append(data), [])
    }

    func testInvalidCharacterReplacedOnNextLineAfterCr() {
        let line = "test\r✨string\r"
        var data = Data(line.utf8)
        // Remove 3rd and last byte of "✨"
        data.remove(at: 7)
        XCTAssertEqual(parser.append(data), ["test", "�string"])
    }

    func testMultiLineDataMixedLineEnding() {
        let line = "test1\rtest2\ntest3\r\ntest4\r\rtest5\n\n"
        let data = Data(line.utf8)
        let expected = ["test1", "test2", "test3", "test4", "", "test5", ""]
        XCTAssertEqual(parser.append(data), expected)
    }
}
