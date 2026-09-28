import Foundation

public enum LogFormatter {
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public static func format(_ entry: LogEntry) -> String {
        let fileName = (entry.file as NSString).lastPathComponent
        let delimiter = String(repeating: "=", count: 60)

        var lines: [String] = []
        lines.append(delimiter)
        lines.append("Timestamp: \(timestampFormatter.string(from: entry.timestamp))")
        lines.append("Level: \(entry.level.description)")
        lines.append("")
        lines.append("File: \(fileName)")
        lines.append("Function: \(entry.function)")
        lines.append("Line: \(entry.line)")
        lines.append("")

        if entry.humanReadableError != nil || entry.actualError != nil {
            lines.append("Context:")
            lines.append(entry.message)
            lines.append("")
            if let human = entry.humanReadableError {
                lines.append("Human Readable Error:")
                lines.append(human)
                lines.append("")
            }
            if let actual = entry.actualError {
                lines.append("Actual Error:")
                lines.append(actual)
                lines.append("")
            }
            if let stack = entry.stackTrace {
                lines.append("Stack Trace:")
                lines.append(stack)
                lines.append("")
            }
        } else {
            lines.append("Message:")
            lines.append(entry.message)
            lines.append("")
        }

        lines.append(delimiter)
        return lines.joined(separator: "\n")
    }
}
