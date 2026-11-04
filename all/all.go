// Package all is the one Go framework an iOS app links: gomobile puts the
// whole Go runtime in each framework it makes, so two of them in one app
// crash on each other's symbols. Every package the app needs is therefore
// bound through this one, its functions named by what they are.
package all

import (
	"encoding/json"
	"fmt"
	"strings"
)

// Version names the framework, so Swift can tell it is loaded.
func Version() string { return "all-2" }

// Search returns songs matching q as "id<TAB>name", one a line.
func Search(q string, limit int) string { return search(q, limit) }

// SongURL returns a song's audio as "url<TAB>type<TAB>level".
func SongURL(id int64, level string) string { return songURL(id, level) }

// ParseLyrics returns a parsed LRC as "ms<TAB>text<TAB>translation<TAB>romaji",
// one a line.
func ParseLyrics(lrc, translation string) string { return parseLyrics(lrc, translation) }

// join is the one place a list becomes lines, so the shape is the same
// everywhere Swift reads it.
func join(lines []string) string { return strings.Join(lines, "\n") }

// errf is how a failure crosses: Swift checks the prefix, not an error.
func errf(format string, a ...any) string { return "ERR: " + fmt.Sprintf(format, a...) }

// search returns songs matching q as "id<TAB>name", one a line.
func search(q string, limit int) string {
	if limit <= 0 {
		limit = 5
	}
	body, err := Shared().eapiPost("/api/search/get", map[string]any{
		"s": q, "type": 1, "limit": limit, "offset": 0, "total": "true",
	})
	if err != nil {
		return errf("%v", err)
	}
	var res struct {
		Code   int `json:"code"`
		Result struct {
			Songs []searchedSong `json:"songs"`
		} `json:"result"`
	}
	if err := json.Unmarshal(body, &res); err != nil {
		return errf("decode: %v", err)
	}
	if res.Code != 200 {
		return errf("code %d", res.Code)
	}
	// The search answer leaves the cover out — its album carries only an id
	// and a name — so the songs are asked for again, which is where the
	// sleeve's address comes from. One request for the whole set.
	covers := fetchCovers(res.Result.Songs)
	var out []string
	for _, s := range res.Result.Songs {
		// The artists and the album go with it: the lock screen shows them,
		// and a list of bare titles reads as a list of the same word when
		// the song has many versions.
		var artists []string
		for _, a := range s.Ar {
			artists = append(artists, a.Name)
		}
		// The cover is asked for small: a list of 20 rows does not need
		// the full sleeve, and the CDN resizes on request.
		pic := s.Al.PicURL
		if pic != "" {
			pic += "?param=200y200"
		}
		_ = pic
		out = append(out, fmt.Sprintf("%d\t%s\t%s\t%s\t%s",
			s.ID, s.Name, strings.Join(artists, " / "), s.Al.Name, covers[s.ID]))
	}
	return join(out)
}

// songURL returns a song's audio as "url<TAB>type<TAB>level".
func songURL(id int64, level string) string {
	if level == "" {
		level = "exhigh"
	}
	encode := "mp3"
	if level == "lossless" || level == "hires" {
		encode = "flac"
	}
	body, err := Shared().eapiPost("/api/song/enhance/player/url/v1", map[string]any{
		"ids": fmt.Sprintf("[%d]", id), "level": level, "encodeType": encode,
	})
	if err != nil {
		return errf("%v", err)
	}
	var res struct {
		Code int `json:"code"`
		Data []struct {
			URL           string          `json:"url"`
			Type          string          `json:"type"`
			Level         string          `json:"level"`
			FreeTrialInfo json.RawMessage `json:"freeTrialInfo"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &res); err != nil {
		return errf("decode: %v", err)
	}
	if res.Code != 200 {
		return errf("code %d", res.Code)
	}
	if len(res.Data) == 0 || res.Data[0].URL == "" {
		return errf("unavailable")
	}
	d := res.Data[0]
	if len(d.FreeTrialInfo) > 0 && string(d.FreeTrialInfo) != "null" {
		return errf("vip preview only")
	}
	u := strings.Replace(d.URL, "http://", "https://", 1)
	return fmt.Sprintf("%s\t%s\t%s", u, strings.ToLower(d.Type), d.Level)
}

// parseLyrics returns a parsed LRC as "ms<TAB>text<TAB>translation<TAB>romaji".
func parseLyrics(lrc, translation string) string {
	lines := Build(lrc, translation, "", "")
	var out []string
	for _, l := range lines {
		out = append(out, row(fmt.Sprint(l.At.Milliseconds()), l.Text, l.Translation, l.Romaji))
	}
	return join(out)
}

// searchedSong is what the search answer holds of a song: enough to show a
// row, and not the sleeve, whose address only the song's detail carries.
type searchedSong struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
	Ar   []struct {
		Name string `json:"name"`
	} `json:"ar"`
	Al struct {
		ID     int64  `json:"id"`
		Name   string `json:"name"`
		PicURL string `json:"picUrl"`
	} `json:"al"`
}

// fetchCovers asks for the songs again, by id, and returns each one's
// sleeve: the search answer's albums carry only an id and a name, and the
// address of the picture is in the song's own detail. One request for the
// whole set, so a list of twenty costs one more round trip, not twenty.
func fetchCovers(songs []searchedSong) map[int64]string {
	out := map[int64]string{}
	if len(songs) == 0 {
		return out
	}
	c := make([]map[string]int64, len(songs))
	for i, s := range songs {
		c[i] = map[string]int64{"id": s.ID}
	}
	b, _ := json.Marshal(c)
	body, err := Shared().eapiPost("/api/v3/song/detail", map[string]any{"c": string(b)})
	if err != nil {
		return out
	}
	var res struct {
		Songs []struct {
			ID int64 `json:"id"`
			Al struct {
				PicURL string `json:"picUrl"`
			} `json:"al"`
		} `json:"songs"`
	}
	if json.Unmarshal(body, &res) != nil {
		return out
	}
	for _, s := range res.Songs {
		if s.Al.PicURL != "" {
			out[s.ID] = s.Al.PicURL + "?param=200y200"
		}
	}
	return out
}

// DailyJSON returns the day's recommended songs, as the search's lines:
// "id<TAB>name<TAB>artists<TAB>album<TAB>cover". It needs a session, and
// answers "" without one rather than an error, since not being signed in
// is not a failure.
func DailyJSON(limit int) string {
	if limit <= 0 { limit = 30 }
	body, err := Shared().eapiPost("/api/v3/discovery/recommend/songs", map[string]any{})
	if err != nil {
		return errf("%v", err)
	}
	var res struct {
		Code int `json:"code"`
		Data struct {
			DailySongs []struct {
				ID   int64  `json:"id"`
				Name string `json:"name"`
				Ar   []struct{ Name string } `json:"ar"`
				Al   struct {
					Name   string `json:"name"`
					PicURL string `json:"picUrl"`
				} `json:"al"`
			} `json:"dailySongs"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &res); err != nil {
		return errf("decode: %v", err)
	}
	if res.Code != 200 {
		// Not signed in, most of the time: the caller shows its hint.
		return ""
	}
	var out []string
	for i, s := range res.Data.DailySongs {
		if i >= limit { break }
		var artists []string
		for _, a := range s.Ar { artists = append(artists, a.Name) }
		pic := ""
		if s.Al.PicURL != "" {
			pic = s.Al.PicURL + "?param=200y200"
		}
		out = append(out, row(fmt.Sprint(s.ID), s.Name, strings.Join(artists, " / "), s.Al.Name, pic))
	}
	return join(out)
}
