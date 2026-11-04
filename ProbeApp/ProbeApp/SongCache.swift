import Foundation

// SongCache keeps what has been played on disk, so that playing a song
// again needs no network and no wait: the app's own cache, in the one
// place iOS lets an app keep files it can delete, which the system clears
// when it needs the space.
//
// A file is named after the track's id and the level asked for, as the
// desktop build names its own: the same song at another quality is another
// file, and neither overwrites the other.

actor SongCache {
    static let shared = SongCache()

    private let dir: URL
    private let limit: Int64

    init(limitMB: Int = 512) {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("songs", isDirectory: true)
        limit = Int64(limitMB) * 1024 * 1024
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// url names a song's file. The extension is the format's, not .audio:
    /// AVPlayer reads it to know what it is opening, and a file named
    /// otherwise plays as silence rather than as an error.
    private func url(for id: Int64, level: String, type: String) -> URL {
        dir.appendingPathComponent("\(id)-\(level).\(type)")
    }

    /// any returns the file kept for a song at any level and format, which
    /// is what offline playback needs: a song heard once can play again
    /// with no network at all, and asking for its URL first would make the
    /// cache useless on a train.
    func any(id: Int64) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return nil
        }
        for f in files where f.lastPathComponent.hasPrefix("\(id)-") && f.pathExtension != "lrc" {
            let size = (try? FileManager.default.attributesOfItem(atPath: f.path)[.size] as? Int64) ?? 0
            if size > 0 { return f }
        }
        return nil
    }

    /// The file kept for a song, if it is whole: a partial download is
    /// removed, so a play never starts on a half file.
    func existing(id: Int64, level: String, type: String) -> URL? {
        let f = url(for: id, level: level, type: type)
        let size = (try? FileManager.default.attributesOfItem(atPath: f.path)[.size] as? Int64) ?? 0
        guard size > 0 else { return nil }
        // A file written by a download that was cut is marked by a
        // neighbour: the download writes to .part and renames when done.
        let part = f.appendingPathExtension("part")
        if FileManager.default.fileExists(atPath: part.path) {
            try? FileManager.default.removeItem(at: part)
            try? FileManager.default.removeItem(at: f)
            return nil
        }
        return f
    }

    /// fetch returns the file of a song, downloading it if it is not kept:
    /// the caller gets a local URL, so playback never stalls on the network
    /// once a song has been heard.
    func fetch(id: Int64, level: String, type: String, remote: URL,
               progress: @escaping (Double) -> Void) async throws -> URL {
        if let have = existing(id: id, level: level, type: type) { return have }

        let dest = url(for: id, level: level, type: type)
        let part = dest.appendingPathExtension("part")

        // A session of its own, so a cancelled play cancels its download.
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: cfg)

        // Progress needs a delegate: the async download reports only when
        // it is done.
        let reporter = ProgressReporter(progress)
        let (tmp, resp) = try await session.download(from: remote, delegate: reporter)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw CacheError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        // Move into place through the .part name, so existing() can tell a
        // half download from a whole one.
        try? FileManager.default.removeItem(at: part)
        try FileManager.default.moveItem(at: tmp, to: part)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: part, to: dest)
        trim()
        return dest
    }

    /// trim brings the cache back under its limit, oldest first: the songs
    /// least recently played are the ones to lose.
    private func trim() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys) else { return }

        var entries: [(URL, Date, Int64)] = []
        var total: Int64 = 0
        for f in files {
            let v = try? f.resourceValues(forKeys: Set(keys))
            let size = Int64(v?.fileSize ?? 0)
            entries.append((f, v?.contentModificationDate ?? .distantPast, size))
            total += size
        }
        guard total > limit else { return }

        entries.sort { $0.1 < $1.1 }
        for (f, _, size) in entries {
            guard total > limit else { break }
            try? FileManager.default.removeItem(at: f)
            total -= size
        }
    }

    /// usage reports what is kept, for a settings row.
    func usage() -> (files: Int, bytes: Int64) {
        let keys: [URLResourceKey] = [.fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys) else { return (0, 0) }
        var bytes: Int64 = 0
        for f in files {
            bytes += Int64((try? f.resourceValues(forKeys: Set(keys)))?.fileSize ?? 0)
        }
        return (files.count, bytes)
    }

    // MARK: lyrics

    private func lyricURL(_ id: Int64) -> URL {
        dir.appendingPathComponent("\(id).lrc")
    }

    /// lyrics returns what was parsed for a song before, if it was: the
    /// words are as much of a song as its sound, and offline playback
    /// without them would be a title and silence.
    func lyrics(id: Int64) -> String? {
        guard let s = try? String(contentsOf: lyricURL(id), encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    func putLyrics(_ text: String, id: Int64) {
        do {
            try text.write(to: lyricURL(id), atomically: true, encoding: .utf8)
        } catch {
            NSLog("lyrics write failed: %@", "\(error)")
        }
    }

    // MARK: offsets

    private func offsetURL(_ id: Int64) -> URL {
        dir.appendingPathComponent("\(id).offset")
    }

    /// offset returns how far a song's lyrics were moved before, in
    /// seconds, 0 for one never moved.
    func offset(id: Int64) -> Double {
        guard let s = try? String(contentsOf: offsetURL(id), encoding: .utf8),
              let v = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return 0 }
        return max(-5, min(5, v))
    }

    func putOffset(_ d: Double, id: Int64) {
        if abs(d) < 0.001 {
            try? FileManager.default.removeItem(at: offsetURL(id))
            return
        }
        try? String(format: "%.2f", d).write(to: offsetURL(id), atomically: true, encoding: .utf8)
    }

    func clear() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}

/// ProgressReporter tells the caller how far a download has come, since
/// URLSession's async API reports only its end.
private final class ProgressReporter: NSObject, URLSessionTaskDelegate {
    private let report: (Double) -> Void
    init(_ report: @escaping (Double) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        report(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
}

enum CacheError: LocalizedError {
    case badStatus(Int)
    var errorDescription: String? {
        switch self {
        case .badStatus(let c): return "下载失败（HTTP \(c)）"
        }
    }
}
