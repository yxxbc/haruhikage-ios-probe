package all

import (
	"encoding/json"
	"fmt"
	"strings"
)

// Playlists returns the listener's own playlists as "id<TAB>name<TAB>
// count<TAB>cover", one a line, and "" when not signed in: without a
// session there is no one to ask for.
func Playlists() string {
	// Who is signed in, and their id: the playlist call is by user.
	uid, ok := userID()
	if !ok {
		return ""
	}
	body, err := Shared().eapiPost("/api/user/playlist", map[string]any{
		"uid": fmt.Sprint(uid), "limit": 200, "offset": 0,
	})
	if err != nil {
		return errf("%v", err)
	}
	var res struct {
		Code     int `json:"code"`
		Playlist []struct {
			ID         int64  `json:"id"`
			Name       string `json:"name"`
			TrackCount int    `json:"trackCount"`
			CoverURL   string `json:"coverImgUrl"`
		} `json:"playlist"`
	}
	if err := json.Unmarshal(body, &res); err != nil {
		return errf("decode: %v", err)
	}
	if res.Code != 200 {
		return ""
	}
	var out []string
	for _, p := range res.Playlist {
		pic := ""
		if p.CoverURL != "" {
			pic = p.CoverURL + "?param=200y200"
		}
		out = append(out, row(fmt.Sprint(p.ID), p.Name, fmt.Sprint(p.TrackCount), pic))
	}
	return join(out)
}

// PlaylistSongs returns a playlist's songs, in the same shape the search
// answers: "id<TAB>name<TAB>artists<TAB>album<TAB>cover".
//
// The detail call carries the first hundred or so; more are asked for by
// page, since a playlist of a thousand songs is a page that must not wait
// for all of them at once.
func PlaylistSongs(id int64) string {
	body, err := Shared().eapiPost("/api/v6/playlist/detail", map[string]any{"id": fmt.Sprint(id)})
	if err != nil {
		return errf("%v", err)
	}
	var res struct {
		Code      int `json:"code"`
		Playlist  struct {
			TrackCount int `json:"trackCount"`
			Tracks     []struct {
				ID   int64  `json:"id"`
				Name string `json:"name"`
				Ar   []struct{ Name string } `json:"ar"`
				Al   struct {
					Name   string `json:"name"`
					PicURL string `json:"picUrl"`
				} `json:"al"`
			} `json:"tracks"`
		} `json:"playlist"`
	}
	if err := json.Unmarshal(body, &res); err != nil {
		return errf("decode: %v", err)
	}
	if res.Code != 200 {
		return errf("code %d", res.Code)
	}
	// Beyond what the detail carries, the rest come a page at a time.
	songs := res.Playlist.Tracks
	if res.Playlist.TrackCount > len(songs) {
		for offset := len(songs); offset < res.Playlist.TrackCount; offset += 500 {
			page, err := Shared().eapiPost("/api/v6/playlist/track/all", map[string]any{
				"id": fmt.Sprint(id), "limit": 500, "offset": offset,
			})
			if err != nil {
				break
			}
			var more struct {
				Songs []struct {
					ID   int64  `json:"id"`
					Name string `json:"name"`
					Ar   []struct{ Name string } `json:"ar"`
					Al   struct {
						Name   string `json:"name"`
						PicURL string `json:"picUrl"`
					} `json:"al"`
				} `json:"songs"`
			}
			if json.Unmarshal(page, &more) != nil || len(more.Songs) == 0 {
				break
			}
			songs = append(songs, more.Songs...)
		}
	}
	var out []string
	for _, s := range songs {
		var artists []string
		for _, a := range s.Ar {
			artists = append(artists, a.Name)
		}
		pic := ""
		if s.Al.PicURL != "" {
			pic = s.Al.PicURL + "?param=200y200"
		}
		out = append(out, row(fmt.Sprint(s.ID), s.Name, strings.Join(artists, " / "), s.Al.Name, pic))
	}
	return join(out)
}
