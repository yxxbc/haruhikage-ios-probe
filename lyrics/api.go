package lyrics

import (
	"strconv"
	"strings"
)

// ParseJSON parses an LRC and an optional translation, and returns one line
// per lyric as "ms<TAB>text<TAB>translation". gomobile binds strings, so
// the lines cross as text rather than as []Line.
func ParseJSON(lrc, translation string) string {
	lines := Build(lrc, translation, "", "")
	if len(lines) == 0 {
		return ""
	}
	out := make([]string, 0, len(lines))
	for _, l := range lines {
		out = append(out, strconv.FormatInt(l.At.Milliseconds(), 10)+"\t"+l.Text+"\t"+l.Translation+"\t"+l.Romaji)
	}
	return strings.Join(out, "\n")
}

// Version answers without a request, so a Swift side can tell the module
// is loaded.
func Version() string { return "lyrics-1" }
