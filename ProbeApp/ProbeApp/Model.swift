import Foundation
import AVFoundation
import All

// Model is the app's state: what plays, what was searched, and the lyrics
// of what plays. It is the smallest thing that closes the loop — sign in,
// find a song, play it, see its words — and deliberately not a design.

struct Playlist: Identifiable, Hashable {
    let id: Int64
    let name: String
    let count: Int
    let cover: String
    var coverURL: URL? { URL(string: cover) }
}

struct Song: Identifiable, Hashable, Codable {
    let id: Int64
    let name: String
    let artist: String
    let album: String
    let cover: String

    init(id: Int64, name: String, artist: String = "", album: String = "", cover: String = "") {
        self.id = id; self.name = name; self.artist = artist
        self.album = album; self.cover = cover
    }

    var coverURL: URL? { URL(string: cover) }
}

struct LyricLine: Identifiable {
    let id = UUID()
    let at: Double      // seconds
    let text: String
    let translation: String
    let romaji: String
}

@MainActor
final class Model: ObservableObject {
    @Published var query = "晴天 周杰伦"
    @Published var songs: [Song] = []
    @Published var lyrics: [LyricLine] = []
    @Published var current: Song?
    @Published var playing = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    /// offset moves the lyrics against the music, in seconds, by song: a
    /// correction made once holds the next time the song plays, as the
    /// desktop build keeps it. Saved with the cache, since iOS has no
    /// preferences file the Go side could reach.
    @Published var offset: Double = 0
    @Published var who = "未登录"
    @Published var busy = ""
    /// toast is a message shown once and cleared: a queue that ran out of
    /// playable songs has to say so rather than going quiet.
    @Published var toast = ""
    @Published var qrURL: String?
    @Published var qrKey: String?
    @Published var qrMatrix: QRMatrix?

    @Published var daily: [Song] = []
    @Published var playlists: [Playlist] = []
    /// liked marks the songs the listener liked, by id: it is what the
    /// heart on a row shows, and it is kept in memory between launches
    /// only until the session is restored.
    @Published var liked: Set<Int64> = []
    /// searches and played mirror what History keeps, so the view redraws
    /// when either changes.
    @Published var searches: [String] = []
    @Published var played: [Song] = []
    @Published var playlistSongs: [Song] = []
    @Published var openPlaylist: Playlist?
    @Published var homeLoading = false
    @Published var queue: [Song] = []
    @Published var queueAt = 0
    @Published var cacheNote = ""
    @Published var downloaded = 0.0

    /// skipped counts the songs this queue pass has failed on: a queue
    /// where every song fails would otherwise walk itself forever, one
    /// request a second, which is a spinner, a flat battery and a rate
    /// limit all at once.
    private var skipped = 0
    private var player: AVPlayer?
    private var ticker: Task<Void, Never>?
    private var poller: Task<Void, Never>?
    private var endedObserver: NSObjectProtocol?

    // MARK: session

    /// reloadHistory reads what History holds, for the view to show.
    func reloadHistory() {
        searches = History.searches
        played = History.played
    }

    func restoreSession() {
        if let saved = Keychain.load(), !saved.isEmpty {
            _ = AllRestore(saved)
        }
        refreshWho()
        if who != "未登录" {
            loadPlaylists()
            loadLiked()
        }
    }

    func cancelLogin() {
        poller?.cancel()
        qrKey = nil; qrURL = nil; qrMatrix = nil
    }

    func refreshWho() {
        let r = AllLoggedIn()
        if r.hasPrefix("ERR:") { who = "问服务器失败"; return }
        who = r.isEmpty ? "未登录" : String(r.split(separator: "\t").first ?? "已登录")
    }

    func startLogin() {
        let key = AllQRKey()
        guard !key.hasPrefix("ERR:") else { busy = "取二维码失败"; return }
        qrKey = key
        qrURL = AllQRLoginURL(key)
        qrMatrix = QRMatrix(AllQRImage(key))
        poller?.cancel()
        poller = Task { [weak self] in
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, let k = self.qrKey else { return }
                let st = AllQRCheck(k)
                if st.hasPrefix("ERR:") { continue }
                let code = Int64(st.split(separator: "\t").first ?? "") ?? 0
                if code == AllQRConfirmed {
                    let cookie = AllSession()
                    _ = Keychain.save(cookie)
                    await MainActor.run {
                        self.qrKey = nil; self.qrURL = nil; self.qrMatrix = nil
                        self.refreshWho()
                        self.loadPlaylists()
                        self.loadLiked()
                        self.loadHome()
                    }
                    return
                }
                if code == AllQRExpired {
                    await MainActor.run { self.qrKey = nil; self.qrURL = nil; self.qrMatrix = nil; self.busy = "二维码过期" }
                    return
                }
            }
        }
    }

    // MARK: search

    /// loadHome fills the day's songs, once a session is there: without
    /// one the service answers nothing, and the view shows its hint.
    func loadHome() {
        homeLoading = true
        Task.detached {
            let out = AllDailyJSON(30)
            let list = Self.songs(from: out)
            await MainActor.run {
                self.homeLoading = false
                if !list.isEmpty { self.daily = list }
            }
        }
    }

    /// loadLiked fills the marks: the heart on a row reads it, and one the
    /// listener presses changes it.
    func loadLiked() {
        Task.detached {
            let out = AllLikedIDs()
            guard !out.hasPrefix("ERR:"), !out.isEmpty else { return }
            let ids = Set(out.split(separator: "\n").compactMap { Int64($0) })
            await MainActor.run { self.liked = ids }
        }
    }

    /// toggleLike marks the song playing, or the one a row names, and
    /// reads the service's answer as the truth rather than assuming.
    func toggleLike(_ song: Song) {
        let want = !liked.contains(song.id)
        Task.detached {
            let r = AllLike(song.id, want)
            guard r.isEmpty else {
                await MainActor.run { self.busy = "收藏失败" }
                return
            }
            await MainActor.run {
                if want { self.liked.insert(song.id) } else { self.liked.remove(song.id) }
            }
        }
    }

    /// loadPlaylists asks for the listener's own playlists: empty until
    /// signed in, since there is no one to ask for.
    func loadPlaylists() {
        Task.detached {
            let out = AllPlaylists()
            guard !out.hasPrefix("ERR:"), !out.isEmpty else { return }
            let list = Fields.lines(out).compactMap { line -> Playlist? in
                let f = Fields.of(line)
                guard f.count >= 2, let id = Int64(f[0]) else { return nil }
                return Playlist(id: id, name: f[1],
                                count: f.count > 2 ? Int(f[2]) ?? 0 : 0,
                                cover: f.count > 3 ? f[3] : "")
            }
            await MainActor.run { self.playlists = list }
        }
    }

    /// open asks for a playlist's songs, then plays nothing: the list is
    /// shown first, and a tap starts it.
    func open(_ p: Playlist) {
        openPlaylist = p
        playlistSongs = []
        Task.detached {
            let out = AllPlaylistSongs(p.id)
            let list = Self.songs(from: out)
            await MainActor.run { self.playlistSongs = list }
        }
    }

    nonisolated static func songs(from out: String) -> [Song] {
        Fields.lines(out).compactMap { line in
            let f = Fields.of(line)
            guard f.count >= 2, let id = Int64(f[0]) else { return nil }
            return Song(id: id, name: f[1],
                        artist: f.count > 2 ? f[2] : "",
                        album: f.count > 3 ? f[3] : "",
                        cover: f.count > 4 ? f[4] : "")
        }
    }

    func search() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        defer { searches = History.searches }
        // Kept before the answer comes: a search that finds nothing is
        // still a search the listener made.
        History.remember(q)
        busy = "搜索中"
        Task.detached {
            let out = AllSearch(q, 20)
            await MainActor.run {
                self.busy = ""
                guard !out.hasPrefix("ERR:") else { self.busy = out; return }
                self.songs = out.split(separator: "\n").compactMap { line in
                    let f = line.split(separator: "\t", omittingEmptySubsequences: false)
                    guard f.count >= 2, let id = Int64(f[0]) else { return nil }
                    return Song(id: id,
                                name: String(f[1]),
                                artist: f.count > 2 ? String(f[2]) : "",
                                album: f.count > 3 ? String(f[3]) : "",
                                cover: f.count > 4 ? String(f[4]) : "")
                }
            }
        }
    }

    // MARK: play

    /// play plays a song in the list, and queues the rest after it: the
    /// songs below it, then the ones above, so that a search result plays
    /// through rather than stopping at one.
    func play(_ song: Song) { play(song, in: songs) }

    func play(_ song: Song, in list: [Song]) {
        _ = list
        guard let at = list.firstIndex(of: song) else { return }
        queue = Array(list[at...]) + Array(list[..<at])
        queueAt = 0
        skipped = 0
        startQueued()
    }

    /// startQueued plays the song the queue is at: from the cache when it
    /// has been heard, else downloading it first, so that once a song has
    /// played it plays again without waiting.
    private func startQueued() {
        guard queueAt < queue.count else { return }
        let song = queue[queueAt]
        current = song
        History.notePlayed(song)
        busy = "取播放地址"
        downloaded = 0
        let id = song.id
        Task.detached {
            // Kept from a previous play: no network at all, which is what
            // makes the cache worth having on a train.
            if let kept = await SongCache.shared.any(id: id) {
                await MainActor.run {
                    self.busy = ""
                    self.cacheNote = "离线播放"
                    self.start(kept)
                }
                let off = await SongCache.shared.offset(id: id)
                await MainActor.run { self.offset = off }
                await self.loadLyricsOffline(id)
                return
            }
            let out = AllSongURL(id, "exhigh")
            let fields = out.split(separator: "\t")
            guard !out.hasPrefix("ERR:"), fields.count >= 2,
                  let remote = URL(string: String(fields[0])) else {
                await MainActor.run { self.failed("这首放不了") }
                return
            }
            // The format comes back with the URL: the file's extension is
            // what tells the player what it is opening.
            let type = String(fields[1])
            await MainActor.run { self.busy = "下载中"; self.cacheNote = "" }
            do {
                let file = try await SongCache.shared.fetch(id: id, level: "exhigh", type: type, remote: remote) { p in
                    Task { @MainActor in self.downloaded = p }
                }
                await MainActor.run {
                    self.busy = ""
                    self.start(file)
                    self.loadLyrics(id)
                }
                let off = await SongCache.shared.offset(id: id)
                await MainActor.run { self.offset = off }
            } catch {
                // The network is the reason most of the time; the song is
                // still playable from the stream it points at.
                await MainActor.run {
                    self.cacheNote = "缓存失败，直接播放"
                    self.busy = ""
                    self.start(remote)
                    self.loadLyrics(id)
                }
            }
        }
    }

    func next() {
        guard !queue.isEmpty else { return }
        queueAt += 1
        if queueAt >= queue.count { queueAt = 0 }
        startQueued()
    }

    func prev() {
        guard !queue.isEmpty else { return }
        // Going back is a choice: it starts the count again, so a queue
        // that failed is tried once more.
        skipped = 0
        queueAt = queueAt > 0 ? queueAt - 1 : queue.count - 1
        startQueued()
    }

    /// failed moves past a song that would not play, or stops when there is
    /// nothing left to try.
    private func failed(_ why: String) {
        let walk = QueueWalk(skipped: skipped, count: queue.count)
        switch walkFail(walk) {
        case .stop:
            busy = ""
            cacheNote = ""
            playing = false
            player?.pause()
            NowPlaying.shared.show(title: nil)
            toast = why.isEmpty ? "队列里的歌都放不了" : why
            skipped = 0
        case .advance(let next):
            skipped = next
            self.next()
        }
    }

    private func start(_ url: URL) {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.pause()
        if let o = endedObserver { NotificationCenter.default.removeObserver(o) }
        let p = AVPlayer(url: url)
        player = p
        p.play()
        playing = true
        claimRemote()
        publishNowPlaying()
        // The duration is unknown until the item is ready, and a lock screen
        // without it draws no scrubber: publish again when it is.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            await MainActor.run { self?.publishNowPlaying() }
        }
        // A song ends: the next one starts, which is what makes a queue a
        // queue rather than a list of one.
        endedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.next()
        }
        playing = true
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                await MainActor.run {
                    guard let self else { return }
                    self.position = self.player?.currentTime().seconds ?? 0
                    let d = self.player?.currentItem?.duration.seconds ?? 0
                    if d.isFinite, d > 0 { self.duration = d }
                    // Only a player that has started and stopped is paused:
                    // reading rate alone says paused during the turn after
                    // play(), when the item is still preparing, and the lock
                    // screen would drop its controls for that frame.
                    if let p = self.player, p.timeControlStatus == .paused {
                        self.playing = false
                    } else if (self.player?.rate ?? 0) > 0 {
                        self.playing = true
                    }
                }
            }
        }
    }

    /// claimRemote takes the lock screen's commands once, pointed at this
    /// model: play, pause, next, previous, and the scrubber.
    private func claimRemote() {
        guard let p = player else { return }
        NowPlaying.shared.start(
            player: p,
            onPlay: { [weak self] in self?.resume() },
            onPause: { [weak self] in self?.pause() },
            onNext: { [weak self] in self?.next() },
            onPrev: { [weak self] in self?.prev() },
            onSeek: { [weak self] t in self?.seek(t) }
        )
    }

    private func resume() {
        player?.play()
        playing = true
        publishNowPlaying()
    }

    private func pause() {
        player?.pause()
        playing = false
        publishNowPlaying()
    }

    func seek(_ t: Double) {
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 600))
        position = t
        publishNowPlaying()
    }

    /// publishNowPlaying says what plays, so the lock screen shows it:
    /// called when the song, its state or its place changes.
    private func publishNowPlaying() {
        guard let s = current else {
            NowPlaying.shared.show(title: nil)
            return
        }
        let dur = player?.currentItem?.duration.seconds ?? 0
        NowPlaying.shared.show(
            title: s.name, artist: s.artist, album: s.album,
            duration: dur.isFinite ? dur : 0,
            position: player?.currentTime().seconds ?? 0,
            // Not the player's rate: right after play() it is still 0, and
            // a lock screen told "paused" shows no controls at all.
            playing: playing
        )
    }

    func toggle() {
        guard let p = player else { return }
        if p.rate > 0 { p.pause() } else { p.play() }
        playing = p.rate > 0
        publishNowPlaying()
    }

    /// loadLyricsOffline fills the words from what was kept, for a song
    /// that plays from the cache with no network to ask.
    private func loadLyricsOffline(_ id: Int64) async {
        if let kept = await SongCache.shared.lyrics(id: id) {
            await MainActor.run { self.lyrics = Self.parse(kept) }
        }
    }

    nonisolated private static func parse(_ raw: String) -> [LyricLine] {
        Fields.lines(raw).compactMap { line in
            let f = Fields.of(line)
            guard f.count >= 2, let ms = Double(f[0]) else { return nil }
            let text = f[1]
            // 作词：周杰伦 与编曲 are timed lines like any other, but they are
            // not what anyone sings: the desktop build drops them, and so
            // does this.
            if AllIsCredit(text) { return nil }
            return LyricLine(at: ms / 1000, text: text,
                             translation: f.count > 2 ? f[2] : "",
                             romaji: f.count > 3 ? f[3] : "")
        }
    }

    private func loadLyrics(_ id: Int64) {
        Task.detached {
            let out = AllParseLyrics("", "") // warm the framework
            _ = out
            let raw = AllLyricsFor(id)
            guard !raw.hasPrefix("ERR:"), !raw.isEmpty else {
                await MainActor.run { self.lyrics = [] }
                return
            }
            await SongCache.shared.putLyrics(raw, id: id)
            let parsed = Model.parse(raw)
            await MainActor.run { self.lyrics = parsed }
        }
    }

    /// The line sung now, for the view to light up: the offset moves the
    /// words, not the song, so the music plays where it is.
    func currentLine() -> LyricLine? {
        lyrics.last { $0.at <= position + offset + 0.25 }
    }

    /// shift moves the lyrics by d seconds and keeps it for this song.
    func shift(_ d: Double) {
        guard let id = current?.id else { return }
        offset = max(-5, min(5, offset + d))
        Task { await SongCache.shared.putOffset(offset, id: id) }
    }

    func resetOffset() {
        guard let id = current?.id else { return }
        offset = 0
        Task { await SongCache.shared.putOffset(0, id: id) }
    }
}
