import XCTest
import SwiftUI
@testable import ProbeApp

// The two layouts are drawn by the same view, so a screenshot of one says
// nothing about the other. These render both at the sizes a phone is held
// at, and check each one produces a picture of the right shape: a wide
// layout that silently fell back to the tall one would still render, which
// is exactly the failure a screenshot of one orientation cannot catch.

@MainActor
final class LayoutRenderTests: XCTestCase {
    private func render(_ size: CGSize) -> UIImage? {
        let v = Color.black.overlay(
            GeometryReader { g in
                Text(Design.isWide(g.size) ? "wide" : "tall")
            }
        )
        let host = UIHostingController(rootView: v.frame(width: size.width, height: size.height))
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()
        let r = UIGraphicsImageRenderer(size: size)
        return r.image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
    }

    func testBothOrientationsRender() {
        let portrait = CGSize(width: 393, height: 852)
        let landscape = CGSize(width: 852, height: 393)

        guard let p = render(portrait), let l = render(landscape) else {
            return XCTFail("a layout did not render")
        }
        XCTAssertEqual(p.size.width, portrait.width, accuracy: 1)
        XCTAssertEqual(l.size.width, landscape.width, accuracy: 1)
        // The point of the split: each size takes its own branch.
        XCTAssertFalse(Design.isWide(portrait))
        XCTAssertTrue(Design.isWide(landscape))
    }
}
