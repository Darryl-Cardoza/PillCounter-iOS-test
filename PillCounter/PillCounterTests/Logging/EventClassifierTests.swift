import Testing
@testable import PillCounter

struct EventClassifierTests {
    @Test func explicitEventAlwaysWins() {
        let entry = LogEntry(level: .error, file: "/Features/Login/LoginViewModel.swift",
                              function: "f", line: 1, message: "anything", event: .dispenseCount)
        #expect(EventClassifier.classify(entry) == .dispenseCount)
    }

    @Test func timeoutClassifiesByExceptionTypeRegardlessOfModule() {
        let entry = LogEntry(level: .error, file: "/Features/History/HistoryViewModel.swift",
                              function: "f", line: 1, message: "load failed",
                              underlyingError: URLError(.timedOut))
        #expect(EventClassifier.classify(entry) == .networkTimeout)
    }

    @Test func moduleAndKeywordRefineMultiActionModule() {
        let sendEntry = LogEntry(level: .error, file: "/Features/HL7/Hl7EventHandler.swift",
                                  function: "f", line: 1, message: "failed to send batch")
        #expect(EventClassifier.classify(sendEntry) == .hl7SendFailed)

        let connectEntry = LogEntry(level: .error, file: "/Features/HL7/Hl7EventHandler.swift",
                                     function: "f", line: 1, message: "failed to connect to PMS")
        #expect(EventClassifier.classify(connectEntry) == .hl7ConnectFailed)
    }

    @Test func hl7SyncQueueClassifiesAsSyncNotGenericHl7() {
        let entry = LogEntry(level: .error, file: "/Features/HL7/Hl7SyncQueue/HL7SyncQueue.swift",
                              function: "f", line: 1, message: "transaction sync failed")
        #expect(EventClassifier.classify(entry) == .transactionSyncFailed)
    }

    @Test func sessionTimeoutIsDistinctFromSessionExpired() {
        let idle = LogEntry(level: .error, file: "/Features/Login/SessionManager.swift",
                             function: "f", line: 1, message: "session ended due to user inactivity")
        #expect(EventClassifier.classify(idle) == .sessionTimeout)

        let serverExpired = LogEntry(level: .error, file: "/Features/Login/SessionManager.swift",
                                      function: "f", line: 1, message: "session expired, server rejected token")
        #expect(EventClassifier.classify(serverExpired) == .sessionExpired)
    }

    @Test func unmatchedModuleAndErrorFallsBackToUnknown() {
        let entry = LogEntry(level: .error, file: "/Core/Utils/SomeUnrelatedHelper.swift",
                              function: "f", line: 1, message: "something odd happened")
        #expect(EventClassifier.classify(entry) == .unknownError)
    }
}
