import XCTest
@testable import LDSwiftEventSource

final class UTF8LineParserTests: XCTestCase {
    func testNoData() {
        let parser = UTF8LineParser()
        XCTAssertEqual(parser.closeAndReset(), [])
    }

    func testEmptyData() {
        let parser = UTF8LineParser()
        XCTAssertEqual(parser.append("".data(using: .utf8)!), [])
        XCTAssertEqual(parser.closeAndReset(), [])
    }

    func testEmptyCrLine() {
        let line = "\r"
        let parser = UTF8LineParser()
        XCTAssertEqual(parser.append(line.data(using: .utf8)!), [])
        XCTAssertEqual(parser.closeAndReset(), [""])
    }

    func testBasicLine() {
        let line = "test string"
        let parser = UTF8LineParser()
        XCTAssertEqual(parser.append(line.data(using: .utf8)!), [])
        XCTAssertEqual(parser.closeAndReset(), [line])
    }

    func testBasicLineCr() {
        let line = "test string"
        let parser = UTF8LineParser()
        let data = (line + "\r").data(using: .utf8)!
        XCTAssertEqual(parser.append(data), [])
        XCTAssertEqual(parser.closeAndReset(), [line])
    }

    func testBasicLineLf() {
        let line = "test string"
        let parser = UTF8LineParser()
        let data = (line + "\n").data(using: .utf8)!
        XCTAssertEqual(parser.append(data), [line])
        XCTAssertEqual(parser.closeAndReset(), [])
    }

    func testBasicLineCrLf() {
        let line = "test string"
        let parser = UTF8LineParser()
        let data = (line + "\r\n").data(using: .utf8)!
        XCTAssertEqual(parser.append(data), [line])
        XCTAssertEqual(parser.closeAndReset(), [])
    }

    func testBasicSplit() {
        let parser = UTF8LineParser()
        XCTAssertEqual(parser.append("test ".data(using: .utf8)!), [])
        XCTAssertEqual(parser.append("string".data(using: .utf8)!), [])
        XCTAssertEqual(parser.closeAndReset(), ["test string"])
    }

    func testUnicodeString() {
        let line = "¯\\_(ツ)_/¯0️⃣🇺🇸Z̮̞̠͙͔ͅḀ̗̞͈̻̗Ḷ͙͎̯̹̞͓G̻O̭̗̮𝓯𝓸𝔁"
        let parser = UTF8LineParser()
        XCTAssertEqual(parser.append(line.data(using: .utf8)!), [])
        XCTAssertEqual(parser.closeAndReset(), [line])
    }

    func testInvalidCharacterReplaced() {
        let line = "test✨string"
        var data = line.data(using: .utf8)!
        // Remove 3rd and last byte of "✨"
        data.remove(at: 6)
        let expected = "test�string"
        let parser = UTF8LineParser()
        XCTAssertEqual(parser.append(data), [])
        XCTAssertEqual(parser.closeAndReset(), [expected])
    }

    func testCodePointSplitNotReplaced() {
        let line = "test✨string"
        let data = line.data(using: .utf8)!
        let data1 = data.subdata(in: 0..<6)
        let data2 = data.subdata(in: 6..<13)
        let parser = UTF8LineParser()
        XCTAssertEqual(parser.append(data1), [])
        XCTAssertEqual(parser.append(data2), [])
        XCTAssertEqual(parser.closeAndReset(), [line])
    }

    func testPartialReplacedOnClose() {
        let line = "test✨"
        var data = line.data(using: .utf8)!
        let expected = "test�"
        data.remove(at: 6)
        let parser = UTF8LineParser()
        XCTAssertEqual(parser.append(data), [])
        XCTAssertEqual(parser.closeAndReset(), [expected])
    }

    func testInvalidCharacterReplacedOnNextLineAfterCr() {
        let line = "test\r✨string"
        var data = line.data(using: .utf8)!
        // Remove 3rd and last byte of "✨"
        data.remove(at: 7)
        let parser = UTF8LineParser()
        XCTAssertEqual(parser.append(data), ["test"])
        XCTAssertEqual(parser.closeAndReset(), ["�string"])
    }

    func testMultiLineDataMixedLineEnding() {
        let line = "test1\rtest2\ntest3\r\ntest4\r\rtest5\n\n"
        let data = line.data(using: .utf8)!
        let expected = ["test1", "test2", "test3", "test4", "", "test5", ""]
        let parser = UTF8LineParser()
        XCTAssertEqual(parser.append(data), expected)
        XCTAssertEqual(parser.closeAndReset(), [])
    }

    static var allTests = [
        ("testNoData", testNoData),
        ("testEmptyData", testEmptyData),
        ("testBasicLine", testBasicLine),
        ("testBasicLineCr", testBasicLineCr),
        ("testBasicLineLf", testBasicLineLf),
        ("testBasicLineCrLf", testBasicLineCrLf),
        ("testBasicSplit", testBasicSplit),
        ("testUnicodeString", testUnicodeString),
        ("testInvalidCharacterReplaced", testInvalidCharacterReplaced),
        ("testCodePointSplitNotReplaced", testCodePointSplitNotReplaced),
        ("testPartialReplacedOnClose", testPartialReplacedOnClose)
    ]
}
