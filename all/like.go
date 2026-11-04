package all

import (
	"encoding/json"
	"fmt"
)

// Like marks a song as liked, or takes the mark off, and answers "" when
// it worked or "ERR: …" when it did not. It needs a session: the service
// keeps the marks by listener.
//
// The THREE field and the time are what the desktop client sends; without
// them the service refuses as a request that is not the client's.
func Like(id int64, like bool) string {
	body, err := Shared().eapiPost("/api/radio/like", map[string]any{
		"alg":     "itembased",
		"trackId": fmt.Sprint(id),
		"like":    like,
		"time":    "3",
	})
	if err != nil {
		return errf("%v", err)
	}
	var res struct {
		Code int    `json:"code"`
		Msg  string `json:"msg"`
	}
	if json.Unmarshal(body, &res) != nil {
		return errf("decode")
	}
	if res.Code != 200 {
		return errf("code %d %s", res.Code, res.Msg)
	}
	return ""
}

// LikedIDs returns the ids of the songs a listener liked, one a line, and
// "" when not signed in: the marks are by account, so there is no one to
// ask for until a session is there.
func LikedIDs() string {
	uid, ok := userID()
	if !ok {
		return ""
	}
	body, err := Shared().eapiPost("/api/song/like/get", map[string]any{"uid": fmt.Sprint(uid)})
	if err != nil {
		return errf("%v", err)
	}
	var res struct {
		Code int `json:"code"`
		Ids  []int64 `json:"ids"`
	}
	if json.Unmarshal(body, &res) != nil {
		return errf("decode")
	}
	if res.Code != 200 {
		return ""
	}
	out := make([]string, 0, len(res.Ids))
	for _, id := range res.Ids {
		out = append(out, fmt.Sprint(id))
	}
	return join(out)
}

// userID returns who is signed in, and whether anyone is: the liked marks
// and the playlists are both kept by account.
func userID() (int64, bool) {
	body, err := Shared().eapiPost("/api/nuser/account/get", map[string]any{})
	if err != nil {
		return 0, false
	}
	var res struct {
		Profile *struct {
			UserID int64 `json:"userId"`
		} `json:"profile"`
	}
	if json.Unmarshal(body, &res) != nil || res.Profile == nil || res.Profile.UserID == 0 {
		return 0, false
	}
	return res.Profile.UserID, true
}
