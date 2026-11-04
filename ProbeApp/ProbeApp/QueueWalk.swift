import Foundation

// QueueWalk is how far a queue pass has failed, and how far it may go: the
// queue walks itself, so a song that will not play hands over to the next,
// and without a count that walk never ends — every song fails, `next` wraps
// to the front, and the app asks the network again and again.
//
// It is a value with one function over it so that the walking can be
// tested without a network, a player or a clock.

struct QueueWalk: Equatable {
    /// How many songs this pass has failed on.
    var skipped: Int
    /// How many songs there are to fail on.
    var count: Int
}

enum QueueStep: Equatable {
    /// Try the next one, this many failed so far.
    case advance(Int)
    /// There is nothing left to try: stop, and say so.
    case stop
}

/// walkFail is what a failed song does: it counts itself and moves on, or,
/// once every song of the queue has failed, it stops.
func walkFail(_ w: QueueWalk) -> QueueStep {
    let next = w.skipped + 1
    if next >= max(1, w.count) { return .stop }
    return .advance(next)
}
