import SwiftUI
import UIKit

// ArtworkColor is the colour a sleeve is known by, as the desktop build
// takes it: the hue most of its vivid pixels share, not its average.
//
// An average is what makes a blurred backdrop look muddy — a white sleeve
// with a gold border averages to beige, and beige blurred and dimmed is
// the grey-brown that reads as "wrong" without saying why. Weighting by
// saturation squared keeps the gold and drops the white.

enum ArtworkColor {
    private static var cache: [URL: UIColor] = [:]
    private static let lock = NSLock()

    static func cached(_ url: URL) -> UIColor? {
        lock.lock(); defer { lock.unlock() }
        return cache[url]
    }

    static func put(_ url: URL, _ c: UIColor) {
        lock.lock(); defer { lock.unlock() }
        if cache.count > 120 { cache.removeAll() }
        cache[url] = c
    }

    /// of returns the sleeve's colour, reading it if it is not known yet.
    static func of(_ url: URL) async -> UIColor? {
        if let c = cached(url) { return c }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let img = UIImage(data: data) else { return nil }
        let c = dominant(in: img)
        put(url, c)
        return c
    }

    /// dominant is the desktop build's algorithm, step for step: pixels
    /// with no colour are skipped, the rest vote by hue, each weighted by
    /// saturation squared times value, and the winner's own colour wins.
    /// An image with no colour at all falls back to its average.
    static func dominant(in img: UIImage) -> UIColor {
        let side = 24
        guard let small = resized(img, side: side), let data = pixels(of: small) else {
            return .gray
        }
        let buckets = 18
        var weight = [Double](repeating: 0, count: buckets)
        var sum = [[Double]](repeating: [0, 0, 0], count: buckets)
        var gray = [Double](repeating: 0, count: 3)
        var counted = 0.0

        for i in stride(from: 0, to: data.count, by: 4) {
            let r = Double(data[i]) / 255, g = Double(data[i + 1]) / 255, b = Double(data[i + 2]) / 255
            gray[0] += r; gray[1] += g; gray[2] += b
            counted += 1
            let (h, s, v) = hsv(r, g, b)
            if s < 0.15 || v < 0.15 { continue }
            let w = s * s * v
            let k = min(buckets - 1, max(0, Int(h / 360 * Double(buckets))))
            weight[k] += w
            sum[k][0] += r * w; sum[k][1] += g * w; sum[k][2] += b * w
        }

        var best = 0
        for k in 1..<buckets where weight[k] > weight[best] { best = k }
        // Only a picture with no colour at all falls back: a small vivid
        // area is still the colour the sleeve is known by, and an area
        // threshold would turn a white sleeve with thin gold into the beige
        // its average is — the mud this exists to avoid.
        guard weight[best] > 0, counted > 0 else {
            guard counted > 0 else { return .gray }
            return UIColor(red: gray[0] / counted, green: gray[1] / counted, blue: gray[2] / counted, alpha: 1)
        }
        let w = weight[best]
        return UIColor(red: sum[best][0] / w, green: sum[best][1] / w, blue: sum[best][2] / w, alpha: 1)
    }

    private static func hsv(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let mx = max(r, g, b), mn = min(r, g, b)
        let d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = 60 * ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = 60 * ((b - r) / d + 2) }
            else { h = 60 * ((r - g) / d + 4) }
        }
        if h < 0 { h += 360 }
        let s = mx == 0 ? 0 : d / mx
        return (h, s, mx)
    }

    private static func resized(_ img: UIImage, side: Int) -> UIImage? {
        let size = CGSize(width: side, height: side)
        let f = UIGraphicsImageRendererFormat.default()
        f.scale = 1
        f.opaque = false
        return UIGraphicsImageRenderer(size: size, format: f).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func pixels(of img: UIImage) -> [UInt8]? {
        guard let cg = img.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return buf
    }
}
