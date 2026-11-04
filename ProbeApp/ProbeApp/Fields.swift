import Foundation

// Fields reads what Go hands over: one record a line, its fields separated
// by tabs.
//
// A field may hold a tab or a line break itself — a song title can — so Go
// escapes those before joining, and this reads them back. Without that a
// title with a tab shifts every field after it, and the artist shows up
// where the album belongs.

enum Fields {
    /// lines splits what Go returned into records, dropping the blank ones
    /// a trailing newline leaves.
    static func lines(_ text: String) -> [String] {
        guard !text.hasPrefix("ERR:") else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    /// of splits one record into its fields, each unescaped.
    static func of(_ line: String) -> [String] {
        line.split(separator: "\t", omittingEmptySubsequences: false).map { unescape(String($0)) }
    }

    /// unescape reads back what Go's escape wrote.
    static func unescape(_ s: String) -> String {
        guard s.contains("\\") else { return s }
        var out = ""
        out.reserveCapacity(s.count)
        var it = s.makeIterator()
        while let c = it.next() {
            guard c == "\\" else { out.append(c); continue }
            switch it.next() {
            case "t": out.append("\t")
            case "n": out.append("\n")
            case "r": out.append("\r")
            case "\\": out.append("\\")
            case let other?: out.append(other)
            case nil: out.append("\\")
            }
        }
        return out
    }
}
