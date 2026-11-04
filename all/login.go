package all

import (
	"encoding/json"
	"fmt"
	"strings"

	"rsc.io/qr"
)

// QRStates are the states the music service reports for a QR login, as the
// app's netease package has them.
const (
	QRExpired   = 800
	QRWaiting   = 801
	QRScanned   = 802
	QRConfirmed = 803
)

// QRKey starts a QR login and returns the key the code is made from, or
// "ERR: …".
func QRKey() string {
	body, err := Shared().eapiPost("/api/login/qrcode/unikey", map[string]any{"type": 3})
	if err != nil {
		return errf("%v", err)
	}
	var res struct {
		Code   int    `json:"code"`
		Unikey string `json:"unikey"`
	}
	if err := json.Unmarshal(body, &res); err != nil {
		return errf("decode: %v", err)
	}
	if res.Unikey == "" {
		return errf("no key (code %d)", res.Code)
	}
	return res.Unikey
}

// QRLoginURL is the URL the code shows, which the app scans with.
func QRLoginURL(key string) string {
	return "https://music.163.com/login?codekey=" + key
}

// QRCheck reports where the login of key is, as "code<TAB>nickname<TAB>
// avatar", or "ERR: …". A code of 803 means the session cookies are in the
// jar, and the app can save them.
func QRCheck(key string) string {
	body, err := Shared().eapiPost("/api/login/qrcode/client/login", map[string]any{"key": key, "type": 3})
	if err != nil {
		return errf("%v", err)
	}
	var r struct {
		Code      int    `json:"code"`
		Message   string `json:"message"`
		Nickname  string `json:"nickname"`
		AvatarURL string `json:"avatarUrl"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return errf("decode: %v", err)
	}
	return fmt.Sprintf("%d\t%s\t%s", r.Code, r.Nickname, r.AvatarURL)
}

// Session returns the cookies a login left, as "name=value; name=value",
// which the Swift side saves to the keychain: the Go side has no keychain
// of its own on iOS, and iOS's is reached from either side but only
// through platform code.
func Session() string {
	c := Shared()
	c.mu.Lock()
	defer c.mu.Unlock()
	var parts []string
	for _, k := range []string{"MUSIC_U", "NMTID", "__csrf"} {
		if v, ok := c.jar[k]; ok && v != "" {
			parts = append(parts, k+"="+v)
		}
	}
	return strings.Join(parts, "; ")
}

// Restore puts a session back, as the Swift side read it from the keychain
// at launch: the app is logged in without scanning again.
func Restore(cookie string) string {
	if cookie == "" {
		return "ERR: empty"
	}
	c := Shared()
	c.mu.Lock()
	defer c.mu.Unlock()
	n := 0
	for _, part := range strings.Split(cookie, ";") {
		name, value, ok := strings.Cut(strings.TrimSpace(part), "=")
		if !ok || name == "" {
			continue
		}
		c.jar[name] = value
		n++
	}
	return fmt.Sprintf("%d cookies", n)
}

// LoggedIn reports whether a session is loaded, by asking the service who
// the listener is: "nickname" when signed in, "" when not, "ERR: …" when
// the call itself failed.
func LoggedIn() string {
	body, err := Shared().eapiPost("/api/nuser/account/get", map[string]any{})
	if err != nil {
		return errf("%v", err)
	}
	var res struct {
		Code    int `json:"code"`
		Profile *struct {
			Nickname string `json:"nickname"`
			UserID   int64  `json:"userId"`
		} `json:"profile"`
	}
	if err := json.Unmarshal(body, &res); err != nil {
		return errf("decode: %v", err)
	}
	if res.Profile == nil {
		return ""
	}
	return fmt.Sprintf("%s\t%d", res.Profile.Nickname, res.Profile.UserID)
}

// QRImage returns a QR code for the login URL of key as "size;hex rows":
// the side of its square in modules, then that many rows of 0/1 hex
// digits, darker module 1. A QR library does the encoding where the app's
// own build does it too (rsc.io/qr), so the code a phone scans is the same
// one the desktop app shows.
//
// The matrix crosses as text because gomobile binds no slices: a row a
// line, a module a character, is the smallest shape that says it.
func QRImage(key string) string {
	code, err := qr.Encode(QRLoginURL(key), qr.M)
	if err != nil {
		return errf("qr: %v", err)
	}
	size := code.Size
	var b strings.Builder
	fmt.Fprintf(&b, "%d", size)
	for y := 0; y < size; y++ {
		b.WriteByte('\n')
		for x := 0; x < size; x++ {
			if code.Black(x, y) {
				b.WriteByte('1')
			} else {
				b.WriteByte('0')
			}
		}
	}
	return b.String()
}
