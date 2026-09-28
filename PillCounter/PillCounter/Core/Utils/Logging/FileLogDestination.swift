import Foundation

public final class FileLogDestination: LogDestination {
    private let fileURL: URL
    private let queue: DispatchQueue

    public init(
        fileURL: URL? = nil,
        queue: DispatchQueue = DispatchQueue(label: "com.pillcounter.applogger.file")
    ) {
        self.queue = queue
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let supportDir = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            )[0]
            self.fileURL = supportDir
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("app.log")
        }
        prepareFile()
    }

    private func prepareFile() {
        let directory = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        var url = fileURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? url.setResourceValues(resourceValues)
    }

    public func write(_ entry: LogEntry, formatted: String) {
        queue.async { [fileURL] in
            guard let data = (formatted + "\n").data(using: .utf8) else { return }
            guard let handle = try? FileHandle(forWritingTo: fileURL) else {
                #if DEBUG
                print("[FileLogDestination] unable to open log file for writing")
                #endif
                return
            }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                #if DEBUG
                print("[FileLogDestination] write failed: \(error)")
                #endif
            }
        }
    }
}
