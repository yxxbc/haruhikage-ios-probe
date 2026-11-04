import Foundation
@testable import ProbeApp

// TestHooks reaches the model's pure parsing without building a model, so
// that a parsing test needs no player, no network and no main actor.
enum TestHooks {
    static func songs(from out: String) -> [Song] {
        Model.songs(from: out)
    }
}
