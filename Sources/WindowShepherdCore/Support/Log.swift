import Foundation
import os

/// Event log: the unified log plus a plain file in ~/Library/Logs/Window Shepherd/,
/// kept under ~256 KB (the previous file is kept as `.1`). Writes happen on a
/// private serial queue, never on the caller's thread.
public enum Log {
    public static let bundleID = "com.windowshepherd.WindowShepherd"
    static let maxSize = 256 * 1024

    private static let queue = DispatchQueue(label: "window-shepherd.log", qos: .utility)
    private static let logger = Logger(subsystem: bundleID, category: "app")
    private static let lock = NSLock()
    private static var _fileURL: URL = FileManager.default
        .urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/Window Shepherd/window-shepherd.log")

    /// Settable so tests can redirect the log.
    public static var fileURL: URL {
        get { lock.lock(); defer { lock.unlock() }; return _fileURL }
        set { lock.lock(); _fileURL = newValue; lock.unlock() }
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    public static func info(_ msg: String) {
        logger.info("\(msg, privacy: .public)")
        let url = fileURL
        let line = stamp.string(from: Date()) + "  " + msg + "\n"
        queue.async { append(line, to: url) }
    }

    /// Waits until every queued line is written (tests).
    public static func flush() { queue.sync {} }

    private static func append(_ line: String, to url: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxSize {
            let old = url.appendingPathExtension("1")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }
}
