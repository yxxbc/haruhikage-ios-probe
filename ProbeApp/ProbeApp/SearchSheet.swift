import SwiftUI

// SearchSheet is the search, over the home: a field, the results, and a
// row that plays what it names. It is a sheet rather than a page because a
// search is a detour, and closing it goes back to what was playing.

struct SearchSheet: View {
    @ObservedObject var m: Model
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    field
                    if m.songs.isEmpty && !m.searches.isEmpty && m.busy.isEmpty {
                        history
                    }
                    results
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        m.songs = []
                        dismiss()
                    }
                }
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .task {
            focused = true
            m.reloadHistory()
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.4))
            TextField("歌曲、歌手", text: $m.query)
                .focused($focused)
                .submitLabel(.search)
                .onSubmit { m.search() }
                .autocorrectionDisabled()
            if !m.query.isEmpty {
                Button { m.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, Design.pageMargin).padding(.vertical, 10)
    }

    /// history is the words searched before, as chips: a tap searches one
    /// again, which is what a phone's search screen does.
    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("最近搜索").font(Design.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Button("清空") {
                    History.clearSearches()
                    m.searches = []
                }
                .font(Design.caption)
                .foregroundStyle(.white.opacity(Design.faint))
            }
            FlowChips(items: m.searches, onTap: { q in
                m.query = q
                m.search()
            }, onDelete: { q in
                History.forget(q)
                m.searches = History.searches
            })
        }
        .padding(.horizontal, Design.pageMargin)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var results: some View {
        if !m.busy.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
        }
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(m.songs) { s in
                    Button {
                        m.play(s, in: m.songs)
                    } label: {
                        HStack(spacing: 12) {
                            CoverImage(url: s.coverURL, side: Design.searchCover, radius: Design.rowCorner)
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
