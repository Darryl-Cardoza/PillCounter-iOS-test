import Testing
import Foundation
@testable import PillCounter

private func tempURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
}

private func pending(_ id: String, at date: Date = Date()) -> Data {
    let stamp = ISO8601DateFormatter().string(from: date)
    return Data("{\"log_id\":\"\(id)\",\"timestamp\":\"\(stamp)\"}".utf8)
}

@Suite(.serialized)
struct LogFileTests {
    @Test func pendingLinesKeepOrderAndIgnoreTextBlocks() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let file = LogFile(fileURL: url)
        file.append("free text\n{not pending}")
        file.appendPending(pending("a"))
        file.append("more text")
        file.appendPending(pending("b"))
        let lines = file.pendingLines()
        #expect(lines.count == 2)
        #expect(lines[0].contains("\"a\"") && lines[1].contains("\"b\""))
    }

    @Test func compactRemovesOnlyGivenLinesAndKeepsText() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let file = LogFile(fileURL: url)
        file.append("keep me")
        file.appendPending(pending("a"))
        file.appendPending(pending("b"))
        file.compact(removing: [file.pendingLines()[0]])
        #expect(file.pendingLines().count == 1)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("keep me"))
    }

    @Test func dropsExpiredCorruptAndOverflowPending() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let file = LogFile(fileURL: url, maxPending: 2, maxAge: 3600)
        file.appendPending(pending("old", at: Date().addingTimeInterval(-7200)))
        file.append("{truncated")
        file.appendPending(pending("1"))
        file.appendPending(pending("2"))
        file.appendPending(pending("3"))
        let lines = file.pendingLines()
        #expect(lines.count == 2)
        #expect(lines[0].contains("\"2\"") && lines[1].contains("\"3\""))
    }

    @Test func startupPurgesFreeTextButKeepsPendingLines() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let queued = String(decoding: pending("keep"), as: UTF8.self)
        let legacy = "====\nTimestamp: t\nMessage:\nold free text\n====\n@@PENDING@@ " + queued + "\nmore old text\n"
        try legacy.write(to: url, atomically: true, encoding: .utf8)

        let file = LogFile(fileURL: url)
        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(!contents.contains("old free text") && !contents.contains("more old text"))
        #expect(!contents.contains("@@PENDING@@"))
        #expect(file.pendingLines() == [queued])
    }

    @Test func startupOnFileWithOnlyFreeTextLeavesItEmpty() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        try "just old text\n".write(to: url, atomically: true, encoding: .utf8)
        _ = LogFile(fileURL: url)
        #expect(try String(contentsOf: url, encoding: .utf8).isEmpty)
    }

    @Test func startupOnEmptyOrMissingFileIsSafe() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let file = LogFile(fileURL: url)
        #expect(file.pendingLines().isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func pendingLineWithUnparseableTimestampIsKept() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let file = LogFile(fileURL: url, maxAge: 1)
        file.appendPending(Data("{\"log_id\":\"x\",\"timestamp\":\"garbage\"}".utf8))
        #expect(file.pendingLines().count == 1)
    }

    @Test func compactingUnknownLineChangesNothing() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let file = LogFile(fileURL: url)
        file.appendPending(pending("a"))
        file.compact(removing: ["{\"not\":\"there\"}"])
        #expect(file.pendingLines().count == 1)
    }

    @Test func pendingPayloadWithNewlineInMessageStaysOneLine() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let file = LogFile(fileURL: url)
        let json = try! JSONSerialization.data(withJSONObject: ["log_id": "n", "message": "a\nb"])
        file.appendPending(json)
        let lines = file.pendingLines()
        #expect(lines.count == 1)
        #expect(!lines[0].contains("\n"))
    }

    @Test func trimsOldestBytesAtLineBoundary() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let file = LogFile(fileURL: url, maxBytes: 400)
        for i in 0..<20 { file.appendPending(pending("id\(i)")) }
        let lines = file.pendingLines()
        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.utf8.count <= 400)
        #expect(!lines.isEmpty && lines.allSatisfy { $0.hasSuffix("}") })
        #expect(!contents.contains("id0\""))
        #expect(contents.contains("id19"))
    }
}
