import XCTest
@testable import ProbeApp

// The queue walks itself: a song that will not play hands over to the next.
// Left alone that is an endless walk — every song fails, next wraps to the
// front, and the app asks the network again and again, a request a turn.

final class QueueTests: XCTestCase {
    // A queue of three, every song failing: the pass stops after three,
    // not after three hundred.
    func testWalkEnds() {
        var w = QueueWalk(skipped: 0, count: 3)
        var steps = 0
        while steps < 100 {
            switch walkFail(w) {
            case .stop:
                XCTAssertEqual(w.skipped, 2, "stopped after \(w.skipped + 1) failures")
                return
            case .advance(let n):
                w.skipped = n
                steps += 1
            }
        }
        XCTFail("the walk did not stop in 100 steps")
    }

    // The passes: two advances then a stop for a queue of three.
    func testWalkSteps() {
        XCTAssertEqual(walkFail(QueueWalk(skipped: 0, count: 3)), .advance(1))
        XCTAssertEqual(walkFail(QueueWalk(skipped: 1, count: 3)), .advance(2))
        XCTAssertEqual(walkFail(QueueWalk(skipped: 2, count: 3)), .stop)
    }

    // A queue of one fails once and stops, rather than wrapping to itself.
    func testSingleSong() {
        XCTAssertEqual(walkFail(QueueWalk(skipped: 0, count: 1)), .stop)
    }

    // An empty queue must not divide by nothing: it stops at once.
    func testEmptyQueue() {
        XCTAssertEqual(walkFail(QueueWalk(skipped: 0, count: 0)), .stop)
    }

    // Going back is a choice, and it wraps: the reason it also resets the
    // count is that a listener going back wants another try.
    @MainActor
    func testPrevWraps() {
        let m = Model()
        m.queue = (0..<3).map { Song(id: Int64($0), name: "歌 \($0)") }
        m.queueAt = 0
        m.prev()
        XCTAssertEqual(m.queueAt, 2)
    }
}
