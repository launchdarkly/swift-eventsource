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
    #endif

    func log(_ level: Level, _ staticMsg: StaticString, _ args: CVarArg...) {
        #if !os(Linux)
        os_log(staticMsg, log: logger, type: level.osLogType, args)
        #endif
    }
}
