import SwiftUI

// NowPlayingView is the full screen: the sleeve large, the words under it,
// and the controls at the foot — the shape the desktop build calls Now
// Playing, on a phone.

struct NowPlayingView: View {
    @ObservedObject var m: Model
    @Environment(\.dismiss) private var dismiss
    @State private var tint: UIColor?
    @State private var dragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                backdrop
                if Design.isWide(geo.size) {
                    wide(geo.size)
                } else {
                    tall(geo.size)
                }
            }
        }
    }

    /// tall stacks the sleeve, its name and the controls, then the words:
    /// the shape a phone held upright wants.
    private func tall(_ size: CGSize) -> some View {
        VStack(spacing: 0) {
            grabber
            Spacer(minLength: 4)
            sleeve(size, ratio: Design.heroCoverRatio)
                .frame(maxHeight: size.height * 0.40)
            title
            scrubber
            transport
            offsetRow
            lyrics
        }
        .padding(.horizontal, Design.pageMargin)
        .padding(.bottom, 14)
    }

    /// wide puts the sleeve and its controls on the left and the words on
    /// the right: held sideways, a stack would squeeze the lyrics into a
    /// strip of two lines.
    private func wide(_ size: CGSize) -> some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(spacing: 0) {
                sleeve(size, ratio: 0.52)
                    .frame(maxHeight: size.height * 0.62)
                title
                scrubber
                transport
                offsetRow
            }
            .frame(width: size.width * 0.46)
            lyrics
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Design.pageMargin)
        .overlay(alignment: .topLeading) { grabber.padding(.leading, 4).padding(.top, 4) }
    }

    /// The backdrop is the sleeve's own colour, made a deep shade of and
    /// shaded: a blurred sleeve would be its average, which for a white
    /// sleeve with a gold border is beige, and beige reads as mud.
    private var backdrop: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let c = tint {
                    // A shade, not a black wash: the hue has to still read,
                    // or every backdrop is the same dark grey and picking
                    // the colour was wasted.
                    LinearGradient(
                        colors: [shade(c, 0.52), shade(c, 0.30)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                // A little of the sleeve itself, very faint: it says which
                // song this is without making the words hard to read.
                AsyncImage(url: m.current?.coverURL) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .blur(radius: 70, opaque: true)
                            .opacity(0.16)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.5), value: m.current?.id)
    }

    /// shade makes a deep, slightly rich version of a colour: dark enough
    /// that white reads over it, keeping its hue.
    private func shade(_ c: UIColor, _ v: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Saturation lifted so a modest colour still shows as itself once
        // dimmed; a grey sleeve keeps its grey.
        let sat = s > 0.12 ? min(max(s * 1.35, 0.45), 0.8) : s
        return Color(hue: h, saturation: sat, brightness: v)
    }

    private var grabber: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.title3).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    /// The sleeve takes a share of the screen's width, not a fixed size:
    /// a small phone and a large one both look right, and a change of
    /// layout does not leave it overflowing.
    private func sleeve(_ size: CGSize, ratio: CGFloat) -> some View {
        CoverImage(url: m.current?.coverURL,
                   side: min(size.width, size.height) * ratio,
                   radius: Design.cardCorner)
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            .scaleEffect(m.playing ? 1 : 0.92)
            .animation(.spring(duration: 0.5, bounce: 0.2), value: m.playing)
    }

    private var title: some View {
        VStack(spacing: 4) {
            Text(m.current?.name ?? "未在播放").font(Design.heroTitle).lineLimit(1)
            Text(m.current?.artist ?? "").font(Design.rowSubtitle).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
        }
        .padding(.top, 22)
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            let d = max(m.duration, 1)
            let shown = dragging ? dragValue : m.position
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18)).frame(height: 4)
                    Capsule().fill(Design.accent).frame(width: g.size.width * min(1, shown / d), height: 4)
                    Circle().fill(.white).frame(width: Design.knob, height: Design.knob)
                        .offset(x: max(0, min(g.size.width - Design.knob, g.size.width * shown / d - Design.knob / 2)))
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragging = true
                        dragValue = max(0, min(1, v.location.x / g.size.width)) * d
                    }
                    .onEnded { _ in
                        m.seek(dragValue)
                        dragging = false
                    })
            }
            .frame(height: 20)
            HStack {
                Text(clock(dragging ? dragValue : m.position))
                Spacer()
                Text(clock(m.duration))
            }
            .font(Design.tiny.monospacedDigit()).foregroundStyle(.white.opacity(0.5))
        }
        .padding(.top, 18)
    }

    private var transport: some View {
        HStack(spacing: 34) {
            likeButton
            Button { m.prev() } label: { Image(systemName: "backward.fill").font(.title) }
            Button { m.toggle() } label: {
                Image(systemName: m.playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: Design.transportBig))
            }
            Button { m.next() } label: { Image(systemName: "forward.fill").font(.title) }
            // The right side is kept the like's width, so the three controls
            // stay centred rather than drifting with the heart.
            Color.clear.frame(width: 26, height: 1)
        }
        .foregroundStyle(.white)
        .padding(.top, 10)
    }

    private var likeButton: some View {
        Button {
            if let s = m.current { m.toggleLike(s) }
        } label: {
            Image(systemName: isLiked ? "heart.fill" : "heart")
                .font(.system(size: Design.heartLarge))
                .foregroundStyle(isLiked ? Design.accent : .white.opacity(0.75))
                .scaleEffect(isLiked ? 1.06 : 1)
                .animation(.spring(duration: 0.3), value: isLiked)
        }
        .disabled(m.current == nil)
    }

    private var isLiked: Bool {
        guard let id = m.current?.id else { return false }
        return m.liked.contains(id)
    }

    /// offsetRow moves the lyrics against the music: a song whose words run
    /// ahead of the voice gets the words put back, and the correction is
    /// kept for that song alone.
    private var offsetRow: some View {
        HStack(spacing: 12) {
            Button { m.shift(-0.5) } label: { Image(systemName: "minus.circle") }
            Button { m.shift(-0.1) } label: { Text("−0.1").font(Design.tiny.monospacedDigit()) }
            Text(m.offset == 0 ? "歌词偏移" : String(format: "%+.1f 秒", m.offset))
                .font(Design.tiny.monospacedDigit())
                .foregroundStyle(m.offset == 0 ? .white.opacity(0.35) : .pink)
                .frame(minWidth: 62)
            Button { m.shift(0.1) } label: { Text("+0.1").font(Design.tiny.monospacedDigit()) }
            Button { m.shift(0.5) } label: { Image(systemName: "plus.circle") }
            if m.offset != 0 {
                Button("复位") { m.resetOffset() }.font(.caption2)
            }
        }
        .foregroundStyle(.white.opacity(0.5))
        .padding(.top, 10)
    }

    private var lyrics: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(m.lyrics) { l in
                        let on = m.currentLine()?.id == l.id
                        VStack(alignment: .leading, spacing: 3) {
                            Text(l.text)
                                .font(.system(size: on ? 22 : 15, weight: on ? .bold : .regular))
                                .foregroundStyle(.white.opacity(on ? 1 : 0.4))
                            if !l.romaji.isEmpty {
                                Text(l.romaji).font(Design.lyricSub).foregroundStyle(.white.opacity(on ? 0.55 : 0.25))
                            }
                            if !l.translation.isEmpty {
                                Text(l.translation).font(Design.lyricSub).foregroundStyle(.white.opacity(on ? 0.7 : 0.3))
                            }
                        }
                        .id(l.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
            }
            .frame(maxHeight: .infinity)
            .onChange(of: m.currentLine()?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(id, anchor: UnitPoint(x: 0, y: 0.5))
                }
            }
        }
        .padding(.top, 14)
    }

    private func clock(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let t = Int(s)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
