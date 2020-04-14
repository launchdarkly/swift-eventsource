import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(UTF8LineParserTests.allTests),
        testCase(LDSwiftEventSourceTests.allTests),
        testCase(EventParserTests.allTests)
    ]
}
#endif
