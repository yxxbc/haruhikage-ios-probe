import XCTest
@testable import ProbeApp

// The orientation split is the one piece of the layout that decides itself,
// so it is the one worth a test: a wrong answer puts the words under the
// sleeve on a turned phone, which is exactly the squeeze the split exists
// to avoid.

final class DesignTests: XCTestCase {
    func testIsWide() {
        // A phone held upright, and the same held sideways.
        XCTAssertFalse(Design.isWide(CGSize(width: 393, height: 852)))
        XCTAssertTrue(Design.isWide(CGSize(width: 852, height: 393)))

        // A pad, both ways.
        XCTAssertFalse(Design.isWide(CGSize(width: 820, height: 1180)))
        XCTAssertTrue(Design.isWide(CGSize(width: 1180, height: 820)))

        // Nearly square: a pad in a split view, which is neither, and stays
        // with the stacked layout until it is clearly wider.
        XCTAssertFalse(Design.isWide(CGSize(width: 600, height: 580)))
        XCTAssertTrue(Design.isWide(CGSize(width: 700, height: 580)))
    }

    // The tokens are numbers the layout reads: none of them may be zero or
    // negative, which would draw nothing without saying why.
    func testTokensAreSane() {
        let lengths: [(String, CGFloat)] = [
            ("pageMargin", Design.pageMargin),
            ("rowCover", Design.rowCover),
            ("barCover", Design.barCover),
            ("searchCover", Design.searchCover),
            ("heroCoverRatio", Design.heroCoverRatio),
            ("qrSide", Design.qrSide),
            ("progressLine", Design.progressLine),
            ("knob", Design.knob),
            ("transportBig", Design.transportBig),
        ]
        for (name, v) in lengths {
            XCTAssertGreaterThan(v, 0, "\(name) is \(v)")
        }
        // A share of the width, so it has to fit one.
        XCTAssertLessThanOrEqual(Design.heroCoverRatio, 1)
        XCTAssertGreaterThan(Design.heroCoverRatio, 0.4)
    }
}
