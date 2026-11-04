package probe

import (
	"encoding/json"
	"fmt"
	"strings"
)

// api.go is the surface Swift sees. gomobile binds only strings, numbers,
// booleans, bytes and structs of those, so each of these answers in text:
// a line or a few lines, and "ERR: " before a failure.

// SearchJSON returns the songs matching q, one a line, as "id<TAB>name".
// The id is what SongURLJSON takes next, so the Swift side can go from a
// search to playing without knowing what a track is.
func SearchJSON(q string, limit int) string {
	if limit <= 0 {
		limit = 5
	}
	body, err := Shared().eapiPost("/api/search/get", map[string]any{
		"s": q, "type": 1, "limit": limit, "offset": 0, "total": "true",
	})
	if err != nil {
		return "ERR: " + err.Error()
	}
	var res struct {
		Code   int `json:"code"`
		Result struct {
			Songs []struct {
				ID   int64  `json:"id"`
				Name string `json:"name"`
			} `json:"songs"`
		} `json:"result"`
	}
	if err := json.Unmarshal(body, &res); err != nil {
		return fmt.Sprintf("ERR: decode: %v (body %.120s)", err, body)
	}
	if res.Code != 200 {
		return fmt.Sprintf("ERR: code %d (body %.120s)", res.Code, body)
	}
	var lines []string
	for _, s := range res.Result.Songs {
		lines = append(lines, fmt.Sprintf("%d\t%s", s.ID, s.Name))
	}
	return strings.Join(lines, "\n")
}

// SongURLJSON returns the URL a song's audio is at, its format and its
// level, as "url<TAB>type<TAB>level", for the Swift side to hand to a
// player. The level is the app's own, "exhigh" for the 320 kbps mp3.
func SongURLJSON(id int64, level string) string {
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
		return "ERR: " + err.Error()
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
		return fmt.Sprintf("ERR: decode: %v (body %.120s)", err, body)
	}
	if res.Code != 200 {
		return fmt.Sprintf("ERR: code %d", res.Code)
	}
	if len(res.Data) == 0 || res.Data[0].URL == "" {
		return "ERR: unavailable"
	}
	d := res.Data[0]
	if len(d.FreeTrialInfo) > 0 && string(d.FreeTrialInfo) != "null" {
		return "ERR: vip preview only"
	}
	// http is refused by iOS without an exception; the CDN serves https.
	u := strings.Replace(d.URL, "http://", "https://", 1)
	return fmt.Sprintf("%s\t%s\t%s", u, strings.ToLower(d.Type), d.Level)
}

// Version answers without a request, so that a Swift side can tell the
// framework is loaded and callable before it tries the network.
func Version() string { return "probe-2" }
