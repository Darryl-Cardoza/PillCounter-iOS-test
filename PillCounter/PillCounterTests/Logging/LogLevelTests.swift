import Testing
@testable import PillCounter

@Suite
struct LogLevelTests {
    @Test func levelsOrderFromVerboseToError() {
        #expect(LogLevel.verbose < LogLevel.debug)
        #expect(LogLevel.debug < LogLevel.info)
        #expect(LogLevel.info < LogLevel.warn)
        #expect(LogLevel.warn < LogLevel.error)
    }

    @Test func descriptionMatchesLevelName() {
        #expect(LogLevel.verbose.description == "VERBOSE")
        #expect(LogLevel.debug.description == "DEBUG")
        #expect(LogLevel.info.description == "INFO")
        #expect(LogLevel.warn.description == "WARN")
        #expect(LogLevel.error.description == "ERROR")
    }

    @Test func loggerConfigDefaultsToError() {
        #expect(LoggerConfig.minimumLogLevel == .error)
    }
}
