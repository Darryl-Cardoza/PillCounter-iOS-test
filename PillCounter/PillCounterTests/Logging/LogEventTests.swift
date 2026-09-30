import Testing
@testable import PillCounter

struct LogEventTests {
    @Test func everyCaseRoundTripsThroughItsRawValue() {
        for event in [LogEvent.loginFailed, .unknownError, .appCrash] {
            #expect(LogEvent(rawValue: event.rawValue) == event)
        }
    }

    @Test func rawValueIsScreamingSnakeCase() {
        #expect(LogEvent.scanFailed.rawValue == "SCAN_FAILED")
        #expect(LogEvent.dispenseCount.rawValue == "DISPENSE_COUNT")
    }
}
