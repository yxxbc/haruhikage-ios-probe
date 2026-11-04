package all

import (
	"encoding/json"
	"fmt"
)

// LyricsFor returns a song's lyrics, parsed, as "ms<TAB>text<TAB>
// translation<TAB>romaji", one a line: the app fetches the LRC and its
// translation and hands both to the parser, and this does the same.
//
// It goes through the eapi, which serves the word-timed lyrics too; those
// are not used here, since the binding hands Swift lines rather than words.
func LyricsFor(id int64) string {
	body, err := Shared().eapiPost("/api/song/lyric/v1", map[string]any{
		"id": fmt.Sprint(id), "cp": false, "tv": 0, "lv": 0, "rv": 0, "kv": 0, "yv": 0, "ytv": 0, "yrv": 0,
	})
	if err != nil {
		return errf("%v", err)
	}
	var res struct {
		Lrc     struct{ Lyric string } `json:"lrc"`
		Tlyric  struct{ Lyric string } `json:"tlyric"`
		Romalrc struct{ Lyric string } `json:"romalrc"`
	}
	if err := json.Unmarshal(body, &res); err != nil {
		return errf("decode: %v", err)
	}
	if res.Lrc.Lyric == "" {
		return ""
	}
	// NetEase's hand-checked romaji where it has one, the kana read here
	// otherwise: the parser does the second by itself.
	return parseLyrics(res.Lrc.Lyric, res.Tlyric.Lyric)
}
