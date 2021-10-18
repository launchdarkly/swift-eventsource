import Foundation

#if !os(Linux)
import os.log
#endif

class Logs {
    enum Level {
        case debug, info, warn, error

#if !os(Linux)
        private static let osLogTypes = [ Level.debug: OSLogType.debug,
                                          Level.info: OSLogType.info,
                                          Level.warn: OSLogType.default,
                                          Level.error: OSLogType.error]
        var osLogType: OSLogType { Level.osLogTypes[self]! }
#endif
    }

#if !os(Linux)
    private let logger: OSLog = OSLog(subsystem: "com.launchdarkly.swift-eventsource", category: "LDEventSource")

    func log(_ level: Level, _ staticMsg: StaticString) {
        os_log(staticMsg, log: logger, type: level.osLogType)
    }

    func log(_ level: Level, _ staticMsg: StaticString, _ arg: CVarArg) {
        os_log(staticMsg, log: logger, type: level.osLogType, arg)
    }

    func log(_ level: Level, _ staticMsg: StaticString, _ arg1: CVarArg, _ arg2: CVarArg) {
        os_log(staticMsg, log: logger, type: level.osLogType, arg1, arg2)
    }
#else
    // We use Any over CVarArg here, because on Linux prior to Swift 5.4 String does not conform to CVarArg
    func log(_ level: Level, _ staticMsg: StaticString, _ args: Any...) { }
#endif
}
