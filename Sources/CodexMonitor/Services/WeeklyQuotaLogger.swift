import Foundation
import OSLog

enum WeeklyQuotaLogger {
    private static let unifiedLogger = Logger(
        subsystem: "com.henry.codex-monitor",
        category: "WeeklyQuotaActivation"
    )
    private static let fileLock = NSLock()
    private static let maximumLogSize = 2 * 1024 * 1024

    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/CodexMonitor", isDirectory: true)
            .appendingPathComponent("weekly-quota.log")
    }

    static func log(_ message: String) {
        unifiedLogger.notice("\(message, privacy: .public)")

        fileLock.withLock {
            let fileManager = FileManager.default
            let url = logURL
            do {
                try fileManager.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let line = "\(formatter.string(from: Date())) \(message)\n"
                let data = Data(line.utf8)
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

                if size >= maximumLogSize {
                    try data.write(to: url, options: .atomic)
                } else if fileManager.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: url, options: .atomic)
                }
            } catch {
                unifiedLogger.error("Failed to write weekly quota log: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
