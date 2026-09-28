import Testing
import Foundation
@testable import PillCounter

@Suite
struct FileLogDestinationTests {
    @Test func writeAppendsFormattedLinesInOrder() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("log")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let queue = DispatchQueue(label: "test.filelogdestination.write")
        let destination = FileLogDestination(fileURL: tempURL, queue: queue)

        destination.write("first entry")
        destination.write("second entry")
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

        destination.write("this must not crash")
        queue.sync {} // reaching this line means the process survived

        #expect(Bool(true))
    }
}
