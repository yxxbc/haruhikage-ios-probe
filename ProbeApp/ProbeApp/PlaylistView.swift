import SwiftUI

// PlaylistView is one playlist's songs: its cover and name at the top, then
// every song, in the order the playlist keeps them.

struct PlaylistView: View {
    @ObservedObject var m: Model
    let playlist: Playlist
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                head
                list
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
        .task { m.open(playlist) }
    }

    private var head: some View {
        HStack(spacing: 14) {
            CoverImage(url: playlist.coverURL, side: Design.rowCover * 1.6, radius: Design.cardCorner)
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name).font(Design.sectionTitle).lineLimit(2)
                Text("\(playlist.count) 首").font(Design.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, Design.pageMargin).padding(.vertical, 12)
    }

    @ViewBuilder
    private var list: some View {
        if m.playlistSongs.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(m.playlistSongs.enumerated()), id: \.element.id) { i, s in
                        Button {
                            m.play(s, in: m.playlistSongs)
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(i + 1)")
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.3))
                                    .frame(width: 22, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.name).font(Design.barTitle)
                                        .foregroundStyle(m.current?.id == s.id ? Design.accent : .white)
                                        .lineLimit(1)
                                    Text(s.artist).font(Design.barSubtitle)
                                        .foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                                }
                                Spacer(minLength: 6)
                            }
                            .padding(.horizontal, Design.pageMargin).padding(.vertical, Design.rowPaddingV)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }
}

// PlaylistGrid is the playlists as cards, as the deskop build's sidebar
// lists them as rows: a phone wants the covers.

struct PlaylistGrid: View {
    @ObservedObject var m: Model
    @State private var open: Playlist?

    private let columns = [GridItem(.flexible(), spacing: Design.gridGap),
                           GridItem(.flexible(), spacing: Design.gridGap)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(m.playlists) { p in
                Button { open = p } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        GeometryReader { g in
                            CoverImage(url: p.coverURL,
                                       side: (g.size.width - Design.gridGap) / 2,
                                       radius: Design.cardCorner)
                        }
                        .aspectRatio(1, contentMode: .fit)
                        Text(p.name).font(Design.caption.weight(.medium))
                            .foregroundStyle(.white).lineLimit(1)
                        Text("\(p.count) 首").font(Design.tiny)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Design.pageMargin)
        .sheet(item: $open) { p in
            NavigationStack { PlaylistView(m: m, playlist: p) }
                .preferredColorScheme(.dark)
        }
    }
}
