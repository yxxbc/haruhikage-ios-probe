import Foundation
import MediaPlayer
import UIKit

// NowPlaying puts what plays on the lock screen and in Control Centre, and
// takes the commands from there: play, pause, next, previous and the
// scrubber. Without it a phone plays audio silently in the background with
// no way to stop it without opening the app.

@MainActor
final class NowPlaying {
    static let shared = NowPlaying()
    private var configured = false
    /// The session ties the player to the now-playing centre: without it
    /// mediaremoted registers the app for a moment and drops it, and no
    /// controls appear anywhere.
    private var session: MPNowPlayingSession?

    /// start claims the now-playing centre and the remote commands, once:
    /// claiming them twice replaces the handlers rather than adding more.
    func start(player: AVPlayer,
               onPlay: @escaping () -> Void,
               onPause: @escaping () -> Void,
               onNext: @escaping () -> Void,
               onPrev: @escaping () -> Void,
               onSeek: @escaping (Double) -> Void) {
        // A session per player: MPNowPlayingSession is what makes iOS treat
        // this app as the one playing, rather than a view with a player in
        // it. Commands are claimed once, as they are global.
        if session == nil {
            let s = MPNowPlayingSession(players: [player])
            s.automaticallyPublishesNowPlayingInfo = false
            s.becomeActiveIfPossible()
            session = s
        }
        guard !configured else { return }
        configured = true
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { _ in onPlay(); return .success }
        c.pauseCommand.addTarget { _ in onPause(); return .success }
        c.togglePlayPauseCommand.addTarget { _ in onPlay(); return .success }
        c.nextTrackCommand.addTarget { _ in onNext(); return .success }
        c.previousTrackCommand.addTarget { _ in onPrev(); return .success }
        c.changePlaybackPositionCommand.addTarget { e in
            guard let ev = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            onSeek(ev.positionTime)
            return .success
        }
    }

    /// show says what plays: the title, the artist, how long it is and
    /// where it is. A nil title clears it, as when nothing plays.
    func show(title: String?, artist: String? = nil, album: String? = nil,
              duration: Double = 0, position: Double = 0, playing: Bool = false) {
        let info = MPNowPlayingInfoCenter.default()
        guard let title, !title.isEmpty else {
            info.nowPlayingInfo = nil
            return
        }
        var d: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artist, !artist.isEmpty { d[MPMediaItemPropertyArtist] = artist }
        if let album, !album.isEmpty { d[MPMediaItemPropertyAlbumTitle] = album }
        if duration > 0 { d[MPMediaItemPropertyPlaybackDuration] = duration }
        info.nowPlayingInfo = d
    }
}
