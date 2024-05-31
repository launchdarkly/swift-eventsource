import Foundation

#if canImport(os)
import os.log
#endif

protocol InternalLogging {
    func log(_ level: Level, _ staticMsg: StaticString)
    func log(_ level: Level, _ staticMsg: StaticString, _ arg: String)
    func log(_ level: Level, _ staticMsg: StaticString, _ arg1: String, _ arg2: String)
}

enum Level {
    case debug, info, warn, error

#if canImport(os)
    private static let osLogTypes = [ Level.debug: OSLogType.debug,
                                      Level.info: OSLogType.info,
                                      Level.warn: OSLogType.default,
                                      Level.error: OSLogType.error]
    var osLogType: OSLogType { Level.osLogTypes[self]! }
#endif
}

#if canImport(os)
class OSLogAdapter: InternalLogging {
    
    private let osLog: OSLog
    
    init(osLog: OSLog) {
        self.osLog = osLog
    }
    
    func log(_ level: Level, _ staticMsg: StaticString) {
        os_log(staticMsg, log: self.osLog, type: level.osLogType)
    }
    
    func log(_ level: Level, _ staticMsg: StaticString, _ arg: String) {
        os_log(staticMsg, log: self.osLog, type: level.osLogType, arg)
    }
    
    func log(_ level: Level, _ staticMsg: StaticString, _ arg1: String, _ arg2: String) {
        os_log(staticMsg, log: self.osLog, type: level.osLogType, arg1, arg2)
    }
}
#endif

class NoOpLogging: InternalLogging {
    func log(_ level: Level, _ staticMsg: StaticString) {}
    func log(_ level: Level, _ staticMsg: StaticString, _ arg: String) {}
    func log(_ level: Level, _ staticMsg: StaticString, _ arg1: String, _ arg2: String) {}
}
