import XCTest
@testable import ProbeApp

// Everything Go hands over crosses as tab-separated text, so this one
// parser is what every list in the app is built from: search, playlists,
// daily. A field off by one there shows up as the artist in the title and
// the cover on the album, which is hard to trace back.
//
// A field may hold a tab or a line break itself — a song title can — so Go
// escapes those before joining, and this reads them back.

final class ParsingTests: XCTestCase {
    // The ordinary case: five fields, all filled.
    func testFullRow() {
        let out = "2668397359\t晴天\t周杰伦\t叶惠美\thttps://p4.example/1.jpg?param=200y200"
        let songs = TestHooks.songs(from: out)
        XCTAssertEqual(songs.count, 1)
        XCTAssertEqual(songs[0].id, 2668397359)
        XCTAssertEqual(songs[0].name, "晴天")
        XCTAssertEqual(songs[0].artist, "周杰伦")
        XCTAssertEqual(songs[0].album, "叶惠美")
        XCTAssertEqual(songs[0].cover, "https://p4.example/1.jpg?param=200y200")
    }

    // A row without a cover, as the daily list has when the album has no
    // picture: the song is still a song.
    func testMissingFields() {
        let songs = TestHooks.songs(from: "1\t歌\t人\t专辑")
        XCTAssertEqual(songs.count, 1)
        XCTAssertEqual(songs[0].cover, "")

        let bare = TestHooks.songs(from: "2\t只有歌名")
        XCTAssertEqual(bare.count, 1)
        XCTAssertEqual(bare[0].name, "只有歌名")
        XCTAssertEqual(bare[0].artist, "")
    }

    // A song whose title holds a tab: Go escapes it as \t, so the fields stay
    // where they belong. Without the escape the line splits into six and the
    // artist shows up where the album belongs.
    func testTabInTheTitle() {
        let songs = TestHooks.songs(from: "3\t歌\\t名\t人\t专辑\t封面")
        XCTAssertEqual(songs.count, 1)
        XCTAssertEqual(songs[0].name, "歌\t名")
        XCTAssertEqual(songs[0].artist, "人", "the artist shifted into another field")
        XCTAssertEqual(songs[0].album, "专辑")
        XCTAssertEqual(songs[0].cover, "封面")
    }

    // A title holding a line break does not become two songs.
    func testNewlineInTheTitle() {
        let songs = TestHooks.songs(from: "4\t上\\n下\t人\t专辑\t封面")
        XCTAssertEqual(songs.count, 1)
        XCTAssertEqual(songs[0].name, "上\n下")
    }

    // A backslash of its own is read back as one: the escape escapes itself,
    // so \\ is a backslash and \t is a tab.
    func testBackslash() {
        XCTAssertEqual(Fields.unescape("x\\\\y"), "x\\y")
        XCTAssertEqual(Fields.unescape("a\\tb"), "a\tb")
        // A lone backslash at the end is kept, not swallowed.
        XCTAssertEqual(Fields.unescape("end\\"), "end\\")
    }

    // An error is not a list of one song called "ERR: …".
    func testErrorIsEmpty() {
        XCTAssertTrue(TestHooks.songs(from: "ERR: code 301").isEmpty)
        XCTAssertTrue(TestHooks.songs(from: "").isEmpty)
    }

    // Blank lines between rows are dropped, not turned into empty songs.
    func testBlankLines() {
        let out = "1\t一\t人\n\n2\t二\t人\n"
        let songs = TestHooks.songs(from: out)
        XCTAssertEqual(songs.count, 2)
        XCTAssertEqual(songs.map(\.name), ["一", "二"])
    }

    // A row with no id is not a song: it would play id 0.
    func testNoID() {
        XCTAssertTrue(TestHooks.songs(from: "不是数字\t歌\t人").isEmpty)
    }
}
