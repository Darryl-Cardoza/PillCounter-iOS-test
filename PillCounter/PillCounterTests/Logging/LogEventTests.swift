import Testing
@testable import PillCounter

struct LogEventTests {
    @Test func everyCaseRoundTripsThroughItsRawValue() {
        for event in [LogEvent.loginSubmitted, .unknownError, .appCrash] {
            #expect(LogEvent(rawValue: event.rawValue) == event)
        }
    }

    @Test func rawValueIsScreamingSnakeCase() {
        #expect(LogEvent.scanTimeout.rawValue == "SCAN_TIMEOUT")
        #expect(LogEvent.dispenseCount.rawValue == "DISPENSE_COUNT")
    }
}
