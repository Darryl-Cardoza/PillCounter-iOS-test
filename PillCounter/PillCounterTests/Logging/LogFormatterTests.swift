import Testing
import Foundation
@testable import PillCounter

@Suite
struct LogFormatterTests {
    @Test func formatsPlainMessageEntry() {
        let entry = LogEntry(
            timestamp: Date(timeIntervalSince1970: 0),
            level: .warn,
            file: "/some/path/BluetoothManager.swift",
            function: "connectToDevice()",
            line: 42,
            message: "Bluetooth device was not available for connection."
        )
        let formatted = LogFormatter.format(entry)
        #expect(formatted.contains("Level: WARN"))
        #expect(formatted.contains("File: BluetoothManager.swift"))
        #expect(formatted.contains("Function: connectToDevice()"))
        #expect(formatted.contains("Message:"))
        #expect(formatted.contains("Bluetooth device was not available for connection."))
    }

    @Test func formatsErrorEntryWithHumanAndActualError() {
        let entry = LogEntry(
            level: .error,
            file: "/some/path/UserRepository.swift",
            function: "getUserProfile()",
            line: 10,
            message: "Failed while retrieving the user profile from the backend.",
            humanReadableError: "The request timed out while communicating with the server.",
            actualError: "URLError: timed out",
            stackTrace: "frame 0\nframe 1"
        )
        let formatted = LogFormatter.format(entry)
        #expect(formatted.contains("Human Readable Error:"))
        #expect(formatted.contains("The request timed out while communicating with the server."))
        #expect(formatted.contains("Actual Error:"))
        #expect(formatted.contains("URLError: timed out"))
        #expect(formatted.contains("Stack Trace:"))
    }

    @Test func formatsMultilineMessageWithoutBreakingBlockDelimiters() {
        let entry = LogEntry(
            level: .error,
            file: "/some/path/Parser.swift",
            function: "parse()",
            line: 5,
            message: "Failed to parse.\nSecond line of context.",
            humanReadableError: "The server response could not be understood.",
            actualError: "DecodingError: multiline\ndetail here"
        )
        let formatted = LogFormatter.format(entry)
        let delimiter = String(repeating: "=", count: 60)
        let delimiterCount = formatted.components(separatedBy: delimiter).count - 1
        #expect(delimiterCount == 2)
        #expect(formatted.contains("Second line of context."))
    }
}
