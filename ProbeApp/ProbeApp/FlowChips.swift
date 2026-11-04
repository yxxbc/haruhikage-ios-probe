import SwiftUI

// FlowChips lays search history out as chips, in rows that wrap: SwiftUI
// has no flow layout, and one row of a dozen searches would run off the
// screen.
//
// The wrap is done by measuring with a rough text width rather than by a
// layout pass: chips are flat and short, and guessing a little wide only
// leaves a gap, not a clipped chip.

struct FlowChips: View {
    let items: [String]
    var onTap: (String) -> Void
    var onDelete: (String) -> Void

    private let line: CGFloat = 34
    private let gap: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let rows = split(width: geo.size.width)
            VStack(alignment: .leading, spacing: gap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: gap) {
                        ForEach(row, id: \.self) { chip($0) }
                    }
                }
            }
        }
        .frame(height: CGFloat(max(1, rows())) * (line + gap))
    }

    private func rows() -> Int {
        // The width is not known here; a second row is reserved whenever
        // there is more than fits on one, which is when there are several.
        items.count > 4 ? 2 : 1
    }

    /// split breaks the items into rows that fit width, by the measured
    /// width of each chip.
    private func split(width: CGFloat) -> [[String]] {
        var out: [[String]] = [[]]
        var x: CGFloat = 0
        for s in items {
            let w = chipWidth(s)
            if x > 0 && x + w > width {
                out.append([])
                x = 0
            }
            out[out.count - 1].append(s)
            x += w + gap
        }
        return out
    }

    private func chipWidth(_ s: String) -> CGFloat {
        // A rough measure: 12pt text, a CJK glyph about 12 points wide, a
        // Latin one about 6.5.
        let text = s.reduce(CGFloat(0)) { $0 + ($1.unicodeScalars.first!.value > 0x2E80 ? 12 : 6.5) }
        return min(text + 36, 220)
    }

    private func chip(_ s: String) -> some View {
        HStack(spacing: 5) {
            Text(s).font(.system(size: 12)).lineLimit(1)
            Button { onDelete(s) } label: {
                Image(systemName: "xmark").font(.system(size: 9))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.white.opacity(0.08), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture { onTap(s) }
    }
}
