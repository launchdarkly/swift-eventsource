import XCTest

import LDSwiftEventSourceTests
import UTF8LineParserTests

var tests = [XCTestCaseEntry]()
tests += LDSwiftEventSourceTests.allTests()
tests += UTF8LineParserTests.allTests()
XCTMain(tests)
