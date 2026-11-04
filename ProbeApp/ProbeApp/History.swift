import Foundation

// History is what was searched and what was played, kept between launches
// the way a phone keeps small things: UserDefaults, which the system backs
// up and the app reads without a request.
//
// It is deliberately not in the keychain: none of it is a secret, and the
// keychain is for the session alone.

enum History {
    private static let searchKey = "searchHistory"
    private static let playedKey = "playedSongs"
    private static let limit = 30

    // MARK: searches

    static var searches: [String] {
        UserDefaults.standard.stringArray(forKey: searchKey) ?? []
    }

    /// remember adds a keyword to the front, once: searching the same word
    /// twice leaves one entry, as the desktop build does.
    static func remember(_ q: String) {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var list = searches.filter { $0 != t }
        list.insert(t, at: 0)
        if list.count > limit { list = Array(list.prefix(limit)) }
        UserDefaults.standard.set(list, forKey: searchKey)
    }

    static func forget(_ q: String) {
        UserDefaults.standard.set(searches.filter { $0 != q }, forKey: searchKey)
    }

    static func clearSearches() {
        UserDefaults.standard.removeObject(forKey: searchKey)
    }

    // MARK: played

    /// played returns the songs played, most recent first.
    static var played: [Song] {
        guard let data = UserDefaults.standard.data(forKey: playedKey),
              let list = try? JSONDecoder().decode([Song].self, from: data) else { return [] }
        return list
    }

    /// notePlayed puts a song at the front of what was played, once, and
    /// keeps a little of the history rather than all of it.
    static func notePlayed(_ s: Song) {
        var list = played.filter { $0.id != s.id }
        list.insert(s, at: 0)
        if list.count > limit { list = Array(list.prefix(limit)) }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: playedKey)
        }
    }

    static func clearPlayed() {
        UserDefaults.standard.removeObject(forKey: playedKey)
    }
}
