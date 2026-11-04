import SwiftUI

// Design is where the sizes and spacings live, in one place, because the
// layout will change: a phone, a pad, a player with lyrics beside the
// sleeve instead of under it. Nothing outside this file should hold a
// number that decides how big or how far apart something is.
//
// The values are the ones the current layout was drawn with; moving them
// here changes nothing on screen, and is what makes changing them later a
// one-file edit rather than a hunt.

enum Design {
    // MARK: spacing

    /// The page's own margin: everything that runs to an edge keeps this
    /// far from it.
    static let pageMargin: CGFloat = 20
    /// Between a row's sleeve and its words.
    static let rowGap: CGFloat = 12
    /// Above and below a row's content.
    static let rowPaddingV: CGFloat = 7
    /// Between sections on the home screen.
    static let sectionGap: CGFloat = 26
    /// Between a section's title and its rows.
    static let sectionTitleGap: CGFloat = 10
    /// Between cards in a grid.
    static let gridGap: CGFloat = 12

    // MARK: radii

    static let rowCorner: CGFloat = 6
    static let cardCorner: CGFloat = 8
    static let sheetCorner: CGFloat = 10

    // MARK: sizes

    /// A row's sleeve on the home screen and a playlist.
    static let rowCover: CGFloat = 52
    /// The player bar's sleeve.
    static let barCover: CGFloat = 42
    /// The sleeve in a search result: a little smaller than home's, since
    /// the list is denser.
    static let searchCover: CGFloat = 46
    /// The sleeve on the now-playing screen, as a share of the screen's
    /// width so that a small phone and a large one both look right.
    static let heroCoverRatio: CGFloat = 0.78
    /// The login code's side.
    static let qrSide: CGFloat = 220
    /// The progress line's height, on the player bar and the now-playing
    /// screen.
    static let progressLine: CGFloat = 2
    /// The draggable knob on the now-playing scrubber.
    static let knob: CGFloat = 10

    // MARK: type

    static let brand = Font.system(size: 22, weight: .heavy)
    static let sectionTitle = Font.system(size: 17, weight: .bold)
    static let rowTitle = Font.system(size: 15, weight: .medium)
    static let rowSubtitle = Font.system(size: 12)
    static let barTitle = Font.system(size: 14, weight: .semibold)
    static let barSubtitle = Font.system(size: 11)
    static let heroTitle = Font.system(size: 20, weight: .bold)
    static let lyricActive = Font.system(size: 23, weight: .bold)
    static let lyricIdle = Font.system(size: 16)
    static let lyricSub = Font.system(size: 11)
    static let caption = Font.system(size: 12)
    static let tiny = Font.system(size: 10)
    static let iconButton = Font.system(size: 17, weight: .semibold)
    static let transportSize: CGFloat = 24
    static let transportFont = Font.system(size: transportSize)
    static let transportBig: CGFloat = 62
    static let heart: CGFloat = 14

    /// A layout is landscape when the screen is wider than it is tall: the
    /// now-playing screen puts its words beside the sleeve there, and
    /// under it otherwise. Read from the size a view is given, not from
    /// the device, so a split view on a pad behaves.
    static func isWide(_ size: CGSize) -> Bool { size.width > size.height * 1.05 }
    static let heartLarge: CGFloat = 22

    // MARK: colours

    /// What plays is marked in pink, as the desktop build's accent.
    static let accent = Color.pink
    static let dim: Double = 0.45
    static let faint: Double = 0.3
}
