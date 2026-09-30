import Foundation

/// Sole owner of dispensesure_logs.txt, a temporary offline queue of remote log
/// payloads (one JSON object per line) that empties as they upload.
/// Every read and rewrite goes through one serial queue.
final class LogFile: @unchecked Sendable {
    // Only for migrating queues written by earlier versions, which prefixed each payload line.
    private static let legacyPrefix = "@@PENDING@@ "

    private static func isPending(_ line: String) -> Bool { line.hasPrefix("{") }

    static let defaultURL: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs", isDirectory: true)
        .appendingPathComponent("dispensesure_logs.txt")

    static let shared = LogFile(fileURL: defaultURL)

    let queue: DispatchQueue
    private let fileURL: URL
    private let maxPending: Int
    private let maxAge: TimeInterval
    private let maxBytes: Int

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(
        fileURL: URL,
        queue: DispatchQueue = DispatchQueue(label: "com.pillcounter.applogger.file"),
        maxPending: Int = LoggerConfig.maxPendingEntries,
        maxAge: TimeInterval = LoggerConfig.pendingMaxAge,
        maxBytes: Int = LoggerConfig.maxLogFileBytes
    ) {
        self.fileURL = fileURL
        self.queue = queue
        self.maxPending = maxPending
        self.maxAge = maxAge
        self.maxBytes = maxBytes
        prepareFile()
    }

    private func prepareFile() {
        let directory = fileURL.deletingLastPathComponent()
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: fileURL.path) {
            let legacy = directory.appendingPathComponent("app.log")
            if fileURL == Self.defaultURL, fm.fileExists(atPath: legacy.path) {
                try? fm.moveItem(at: legacy, to: fileURL)
            } else {
                fm.createFile(atPath: fileURL.path, contents: nil)
            }
        }
        purgeFreeText()
        var url = fileURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? url.setResourceValues(resourceValues)
        try? fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                              ofItemAtPath: fileURL.path)
    }

    /// The file is now only an offline queue; drops free-text blocks written by
    /// earlier versions and strips the legacy line prefix, keeping every queued payload. Idempotent.
    private func purgeFreeText() {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8), !content.isEmpty else { return }
        let pending = content.components(separatedBy: "\n").compactMap { line -> String? in
            if line.hasPrefix(Self.legacyPrefix) { return String(line.dropFirst(Self.legacyPrefix.count)) }
            return Self.isPending(line) ? line : nil
        }
        let result = pending.isEmpty ? "" : pending.joined(separator: "\n") + "\n"
        if result != content { try? result.write(to: fileURL, atomically: true, encoding: .utf8) }
    }

    func append(_ text: String) {
        queue.async { self.appendLocked(text) }
    }

    func appendPending(_ body: Data) {
        guard let json = String(data: body, encoding: .utf8) else { return }
        queue.async {
            self.appendLocked(json)
            self.compactLocked(removing: [])
        }
    }

    func pendingLines() -> [String] {
        queue.sync { readLines().filter(Self.isPending) }
    }

    /// Rewrites the file once: drops `removing`, corrupt/expired pending lines,
    /// pending overflow (oldest first) and, if still too large, the oldest bytes.
    func compact(removing: Set<String>) {
        queue.sync { compactLocked(removing: removing) }
    }

    // MARK: - Queue-confined

    private func appendLocked(_ text: String) {
        guard let data = (text + "\n").data(using: .utf8) else { return }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            #if DEBUG
            print("[LogFile] unable to open log file for writing")
            #endif
            return
        }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            #if DEBUG
            print("[LogFile] write failed: \(error)")
            #endif
        }
    }

    private func readLines() -> [String] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return content.components(separatedBy: "\n")
    }

    private func compactLocked(removing: Set<String>) {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let now = Date()
        var lines = content.components(separatedBy: "\n")

        var keep = lines.map { line -> Bool in
            guard Self.isPending(line) else { return true }
            return !removing.contains(line) && !isCorruptOrExpired(line, now: now)
        }
        let pendingIndices = lines.indices.filter { Self.isPending(lines[$0]) && keep[$0] }
        if pendingIndices.count > maxPending {
            pendingIndices.prefix(pendingIndices.count - maxPending).forEach { keep[$0] = false }
        }
        lines = zip(lines, keep).filter { $0.1 }.map { $0.0 }

        var result = lines.joined(separator: "\n")
        if result.utf8.count > maxBytes {
            result = Self.trimToNewest(result, maxBytes: maxBytes)
        }
        if result == content { return }
        try? result.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func isCorruptOrExpired(_ line: String, now: Date) -> Bool {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return true }
        guard let stamp = object["timestamp"] as? String,
              let date = Self.timestampFormatter.date(from: stamp) else { return false }
        return now.timeIntervalSince(date) > maxAge
    }

    /// Cuts at a line boundary so a partial payload never survives.
    private static func trimToNewest(_ text: String, maxBytes: Int) -> String {
        let tail = String(decoding: Array(text.utf8.suffix(maxBytes)), as: UTF8.self)
        guard let cut = tail.firstIndex(of: "\n") else { return "" }
        return String(tail[tail.index(after: cut)...])
    }
}
