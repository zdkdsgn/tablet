import Foundation

/// Troubleshooting logs in ~/Library/Logs. Writes happen on a background queue, and every file is capped:
/// at `maxSize` it becomes `<name>.1.log` (the previous one is dropped) and a new file starts.
enum AppLog {
    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs", isDirectory: true)
    static let maxSize: UInt64 = 1_000_000
    private static let queue = DispatchQueue(label: "Tablet.log", qos: .utility)

    enum File: String, CaseIterable {
        case app = "Tablet"
        case hid = "Tablet-hid"
        case driver = "Tablet-driver"
        case update = "Tablet-update"
        var url: URL { AppLog.dir.appendingPathComponent(rawValue + ".log") }
        var previous: URL { AppLog.dir.appendingPathComponent(rawValue + ".1.log") }
    }

    /// Appends one line with a timestamp.
    static func write(_ text: String, to file: File) {
        let line = "\(stamp()) \(text)\n"
        queue.async {
            rotateIfNeeded(file)
            let data = Data(line.utf8)
            if let h = try? FileHandle(forWritingTo: file.url) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: file.url)
            }
        }
    }

    /// Caps a file another process writes to (opened with O_APPEND, so it carries on at the new end).
    static func trim(_ file: File) {
        queue.async { rotateIfNeeded(file) }
    }

    /// A handle for another process's output: appends, so the file can be rotated underneath it.
    static func appendingHandle(_ file: File, fresh: Bool) -> FileHandle {
        if fresh { try? FileManager.default.removeItem(at: file.url) }
        let fd = open(file.url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        return fd >= 0 ? FileHandle(fileDescriptor: fd, closeOnDealloc: true) : FileHandle.nullDevice
    }

    private static func rotateIfNeeded(_ file: File) {
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath: file.url.path))?[.size] as? UInt64, size > maxSize else { return }
        try? fm.removeItem(at: file.previous)
        try? fm.copyItem(at: file.url, to: file.previous)
        // truncate in place (not a move): a process appending to it keeps writing into the same file
        if let h = try? FileHandle(forWritingTo: file.url) { try? h.truncate(atOffset: 0); try? h.close() }
    }

    private static func stamp() -> String {
        let f = ISO8601DateFormatter()
        return f.string(from: Date())
    }
}
