import Testing
import Foundation
@testable import PillCounter

private func makeEntry(message: String) -> LogEntry {
    LogEntry(level: .error, file: "/f.swift", function: "f", line: 1, message: message)
}

@Suite
struct FileLogDestinationTests {
    @Test func writeAppendsFormattedLinesInOrder() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("log")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let queue = DispatchQueue(label: "test.filelogdestination.write")
        let destination = FileLogDestination(fileURL: tempURL, queue: queue)

        destination.write(makeEntry(message: "first"), formatted: "first entry")
        destination.write(makeEntry(message: "second"), formatted: "second entry")
        queue.sync {} // drain both async writes before reading

        let contents = try String(contentsOf: tempURL, encoding: .utf8)
        #expect(contents.contains("first entry"))
        #expect(contents.contains("second entry"))
        let firstRange = contents.range(of: "first entry")!
        let secondRange = contents.range(of: "second entry")!
        #expect(firstRange.lowerBound < secondRange.lowerBound)
    }

    @Test func writeToInvalidPathDoesNotCrash() {
        // An existing directory (not a file) makes FileHandle(forWritingTo:) fail deterministically.
        let directoryURL = FileManager.default.temporaryDirectory
        let queue = DispatchQueue(label: "test.filelogdestination.invalid")
        let destination = FileLogDestination(fileURL: directoryURL, queue: queue)

        destination.write(makeEntry(message: "this must not crash"), formatted: "this must not crash")
        queue.sync {} // reaching this line means the process survived

        #expect(Bool(true))
    }
}
