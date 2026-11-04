import XCTest
import UIKit
@testable import ProbeApp

// The colour a sleeve is known by decides the whole backdrop, so it is
// worth testing apart from the screen: a wrong answer there reads as "the
// background looks muddy" and gives no clue why.

final class ArtworkColorTests: XCTestCase {
    /// image makes a square of one colour, the size the analyser shrinks to.
    private func image(_ c: UIColor, side: Int = 24) -> UIImage {
        let f = UIGraphicsImageRendererFormat.default()
        f.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: f).image { ctx in
            c.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    private func rgba(_ c: UIColor) -> (CGFloat, CGFloat, CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    // A sleeve of one strong colour is known by that colour.
    func testPlainColour() {
        for c in [UIColor.systemRed, .systemBlue, .systemGreen] {
            let got = rgba(ArtworkColor.dominant(in: image(c)))
            let want = rgba(c)
            XCTAssertEqual(got.0, want.0, accuracy: 0.12)
            XCTAssertEqual(got.1, want.1, accuracy: 0.12)
            XCTAssertEqual(got.2, want.2, accuracy: 0.12)
        }
    }

    // A white sleeve with a gold band is known by the gold, not by the
    // beige its average would be: this is the case that made the backdrop
    // look like mud.
    func testWhiteWithAGoldBand() {
        let side = 24
        let f = UIGraphicsImageRendererFormat.default()
        f.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: f).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            UIColor(red: 0.85, green: 0.68, blue: 0.25, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: side / 2 - 2, width: side, height: 4))
        }
        let (r, g, b) = rgba(ArtworkColor.dominant(in: img))
        // Gold is warm: red high, blue low. Beige would be nearly equal.
        XCTAssertGreaterThan(r, b + 0.15, "r \(r) b \(b): not gold")
        XCTAssertGreaterThan(g, b, "g \(g) b \(b): not gold")
    }

    // A sleeve that is mostly white with a little gold: the gold still
    // wins, which is what the weight by saturation squared is for. A
    // handful of vivid pixels outweigh a field of white ones.
    func testMostlyWhiteWithLittleGold() {
        let side = 24
        let f = UIGraphicsImageRendererFormat.default()
        f.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: f).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            UIColor(red: 0.85, green: 0.68, blue: 0.25, alpha: 1).setFill()
            // A tenth of the picture, not a band across it.
            ctx.fill(CGRect(x: 2, y: 2, width: 6, height: 6))
        }
        let (r, g, b) = rgba(ArtworkColor.dominant(in: img))
        XCTAssertGreaterThan(r, b + 0.1, "r \(r) b \(b): the white won")
    }

    // A sleeve with no colour at all falls back to its average, not to a
    // hue it does not have.
    func testGraySleeve() {
        let grey = UIColor(white: 0.5, alpha: 1)
        let (r, g, b) = rgba(ArtworkColor.dominant(in: image(grey)))
        XCTAssertEqual(r, g, accuracy: 0.06)
        XCTAssertEqual(g, b, accuracy: 0.06)
        XCTAssertEqual(r, 0.5, accuracy: 0.12)
    }
}
