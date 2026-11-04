import SwiftUI

// QRView draws the matrix the Go side encodes: one square a module, dark
// where the matrix says 1. The code is drawn by SwiftUI rather than handed
// over as an image, so it stays sharp at any size and needs no bitmap to
// cross the bridge.

struct QRMatrix {
    let size: Int
    let rows: [String]

    /// Parses what AllQRImage returns: the side, then a row a line.
    init?(_ text: String) {
        guard !text.hasPrefix("ERR:") else { return nil }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first, let n = Int(first), n > 0 else { return nil }
        lines.removeFirst()
        guard lines.count == n else { return nil }
        size = n
        rows = lines
    }

    func black(_ x: Int, _ y: Int) -> Bool {
        guard y < rows.count else { return false }
        let row = Array(rows[y])
        guard x < row.count else { return false }
        return row[x] == "1"
    }
}

struct QRView: View {
    let matrix: QRMatrix
    var side: CGFloat = 240

    var body: some View {
        Canvas { ctx, size in
            let cell = size.width / CGFloat(matrix.size)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            var path = Path()
            for y in 0..<matrix.size {
                for x in 0..<matrix.size where matrix.black(x, y) {
                    path.addRect(CGRect(x: CGFloat(x) * cell,
                                        y: CGFloat(y) * cell,
                                        width: cell, height: cell))
                }
            }
            ctx.fill(path, with: .color(.black))
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }
}
