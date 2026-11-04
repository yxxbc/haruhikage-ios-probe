import SwiftUI

// CoverImage loads a sleeve and keeps it: a list scrolls past the same
// covers again and again, and asking the network for each pass would make
// it stutter. The cache is the URL's, as URLSession's own is.

struct CoverImage: View {
    let url: URL?
    var side: CGFloat = 48
    var radius: CGFloat = 8

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                // A sleeve that has not come yet: a quiet square, so the row
                // keeps its height and nothing jumps when it does.
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: "music.note")
                        .font(.system(size: side * 0.34))
                        .foregroundStyle(.tertiary))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: url) {
            guard let url else { return }
            if let cached = CoverCache.shared.get(url) { image = cached; return }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let img = UIImage(data: data) else { return }
            CoverCache.shared.put(url, img)
            image = img
        }
    }
}

final class CoverCache {
    static let shared = CoverCache()
    private var items: [URL: UIImage] = [:]
    private let lock = NSLock()
    private var order: [URL] = []
    private let limit = 200

    func get(_ u: URL) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        return items[u]
    }

    func put(_ u: URL, _ i: UIImage) {
        lock.lock(); defer { lock.unlock() }
        items[u] = i
        order.removeAll { $0 == u }
        order.append(u)
        while order.count > limit {
            let old = order.removeFirst()
            items[old] = nil
        }
    }
}
