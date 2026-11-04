import SwiftUI

@main
struct ProbeApp: App {
    var body: some Scene { WindowGroup { RootView().preferredColorScheme(.dark) } }
}

struct RootView: View {
    @StateObject private var m = Model()
    @State private var showNowPlaying = false
    @State private var showSearch = false

    var body: some View {
        ZStack(alignment: .top) {
            Backdrop(url: m.current?.coverURL)
            VStack(spacing: 0) {
                topBar
                content
            }
            if !m.toast.isEmpty {
                Text(m.toast)
                    .font(Design.caption)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.black.opacity(0.82), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.12)))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .task {
                        try? await Task.sleep(nanoseconds: 2_600_000_000)
                        withAnimation { m.toast = "" }
                    }
            }
        }
        .safeAreaInset(edge: .bottom) { playerBar }
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView(m: m).preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showSearch) {
            SearchSheet(m: m).preferredColorScheme(.dark)
        }
        .task {
            m.restoreSession()
            m.reloadHistory()
            // A search at launch, so the history has something in it and
            // the probe proves the write without a tap.
            m.query = "周杰伦"
            m.search()
            // Play one and open the full screen, so a screenshot shows the
            // layout the orientation change is about.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if let first = m.songs.first {
                m.play(first, in: m.songs)
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                showNowPlaying = true
            }
            // Not signed in yet, so the day's songs come back empty: search
            // once to show a list, which is what the screen is for.
            try? await Task.sleep(nanoseconds: 600_000_000)
            m.loadHome()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if m.daily.isEmpty { m.search() }
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Text("春日影").font(Design.brand).tracking(-0.4)
            Spacer()
            Button { showSearch = true } label: {
                Image(systemName: "magnifyingglass").font(Design.iconButton)
            }
            Button { m.startLogin() } label: {
                Image(systemName: m.who == "未登录" ? "qrcode" : "person.crop.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, Design.pageMargin)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        if let q = m.qrMatrix {
            loginPane(q)
        } else if m.homeLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            home
        }
    }

    private func loginPane(_ q: QRMatrix) -> some View {
        VStack(spacing: 16) {
            Text("扫码登录").font(.headline)
            QRView(matrix: q, side: Design.qrSide)
            Text("用网易云 App 扫一扫").font(.caption).foregroundStyle(.secondary)
            Button("关闭") { m.cancelLogin() }.font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var home: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Design.sectionGap) {
                // 每日推荐, as the desktop build opens on: the day's songs,
                // which needs a login and is shown only when there is one.
                if !m.daily.isEmpty {
                    section("每日推荐", songs: m.daily)
                }
                if m.playlists.isEmpty && m.who == "未登录" {
                    // No session, so there are no playlists to ask for: say
                    // so rather than leaving a blank where they would be.
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                        Text("登录后显示你的歌单").font(Design.caption)
                    }
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                if !m.played.isEmpty {
                    // What was played, most recent first: a phone's "keep
                    // listening", as the desktop build has.
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("最近播放").font(Design.sectionTitle).tracking(-0.2)
                            Spacer()
                            Button("清空") {
                                History.clearPlayed()
                                m.played = []
                            }
                            .font(Design.caption)
                            .foregroundStyle(.white.opacity(Design.faint))
                        }
                        .padding(.horizontal, Design.pageMargin)
                        LazyVStack(spacing: 0) {
                            ForEach(m.played.prefix(6)) { s in
                                Button { m.play(s, in: m.played) } label: { row(s) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !m.playlists.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("我的歌单").font(Design.sectionTitle).tracking(-0.2)
                            .padding(.horizontal, Design.pageMargin)
                        PlaylistGrid(m: m)
                    }
                }
                if !m.songs.isEmpty {
                    section("搜索结果", songs: m.songs)
                }
                if m.daily.isEmpty && m.songs.isEmpty {
                    emptyHint
                }
            }
            .padding(.bottom, 20)
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list").font(.system(size: Design.qrSide * 0.15)).foregroundStyle(.white.opacity(0.25))
            Text(m.who == "未登录" ? "登录后显示每日推荐" : "搜索一首歌开始")
                .font(.footnote).foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity).padding(.top, 120)
    }

    private func section(_ title: String, songs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: Design.sectionTitleGap) {
            Text(title).font(Design.sectionTitle).tracking(-0.2)
                .padding(.horizontal, Design.pageMargin)
            LazyVStack(spacing: 0) {
                ForEach(songs) { s in
                    Button { m.play(s, in: songs) } label: { row(s) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func row(_ s: Song) -> some View {
        HStack(spacing: 12) {
            CoverImage(url: s.coverURL, side: Design.rowCover, radius: Design.rowCorner)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.name).font(Design.rowTitle)
                    .foregroundStyle(m.current?.id == s.id ? Color.pink : .white)
                    .lineLimit(1)
                Text(s.artist).font(Design.rowSubtitle).foregroundStyle(.white.opacity(Design.dim)).lineLimit(1)
            }
            Spacer(minLength: 8)
            if m.current?.id == s.id {
                Image(systemName: "waveform").foregroundStyle(Design.accent)
                    .symbolEffect(.variableColor.iterative)
            }
            Button { m.toggleLike(s) } label: {
                Image(systemName: m.liked.contains(s.id) ? "heart.fill" : "heart")
                    .font(.system(size: Design.heart))
                    .foregroundStyle(m.liked.contains(s.id) ? Design.accent : .white.opacity(Design.faint))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Design.pageMargin).padding(.vertical, Design.rowPaddingV)
        .contentShape(Rectangle())
    }

    private var playerBar: some View {
        VStack(spacing: 0) {
            GeometryReader { g in
                let d = max(m.duration, 1)
                ZStack(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.12))
                    Rectangle().fill(Design.accent).frame(width: g.size.width * min(1, m.position / d))
                }
            }
            .frame(height: Design.progressLine)

            Button {
                if m.current != nil { showNowPlaying = true }
            } label: {
                HStack(spacing: 12) {
                    CoverImage(url: m.current?.coverURL, side: Design.barCover, radius: Design.rowCorner)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.current?.name ?? "未在播放")
                            .font(Design.barTitle).lineLimit(1)
                        Text(subtitle).font(Design.barSubtitle)
                            .foregroundStyle(.white.opacity(Design.dim)).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Button { m.prev() } label: { Image(systemName: "backward.fill") }
                        .disabled(m.queue.isEmpty)
                    Button { m.toggle() } label: {
                        Image(systemName: m.playing ? "pause.fill" : "play.fill")
                            .font(Design.transportFont)
                    }
                    .disabled(m.current == nil)
                    Button { m.next() } label: { Image(systemName: "forward.fill") }
                        .disabled(m.queue.isEmpty)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 9)
            }
            .buttonStyle(.plain)
        }
        .background(.ultraThinMaterial)
    }

    private var subtitle: String {
        if !m.busy.isEmpty { return m.busy }
        if m.downloaded > 0 && m.downloaded < 1 {
            return String(format: "缓存 %.0f%%", m.downloaded * 100)
        }
        if !m.cacheNote.isEmpty { return m.cacheNote }
        return m.current?.artist ?? "搜索一首歌"
    }
}

/// Backdrop is the cover's colour behind everything, as the desktop build
/// paints Now Playing: the sleeve itself, blurred and dimmed, fixed to the
/// screen so that it sizes nothing.
struct Backdrop: View {
    let url: URL?
    @State private var tint: UIColor?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let tint {
                    // The sleeve's colour, deep: the same shade the
                    // now-playing screen paints, so the two agree.
                    LinearGradient(colors: [shade(tint, 0.38), .black],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.7), value: url)
        .task(id: url) {
            guard let url else { tint = nil; return }
            tint = await ArtworkColor.of(url)
        }
    }

    private func shade(_ c: UIColor, _ v: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let sat = s > 0.12 ? min(max(s * 1.25, 0.4), 0.72) : s
        return Color(hue: h, saturation: sat, brightness: v)
    }
}
