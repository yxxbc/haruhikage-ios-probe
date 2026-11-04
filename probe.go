// Package probe answers one question: can the music service's API be
// called from Go as iOS builds it, at all?
//
// It is not the app's netease package, which needs the app's own settings
// and keychain (github.com/egoist/mygo) and so cannot run on iOS, but it
// copies that package's eapi call closely enough that a call which works
// here works there: the same host, cipher, headers and device identity
// (internal/netease/eapi.go). Only what the keychain and the user data
// directory gave it are replaced, by a device ID kept in the cache
// directory, which iOS has too.
//
// The cipher is the app's, line for line: eapiEncrypt below is that
// function with its import changed, so that what this proves is about the
// network and the device, not about a cipher reimplemented and got wrong.
package probe

import (
	"bytes"
	"crypto/aes"
	"crypto/md5"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	eapiDomain = "https://interfacepc.music.163.com"
	eapiKey    = "e82ckenh8dichen8"
	eapiUA     = "NeteaseMusic 9.0.90/5038 (iPhone; iOS 16.2; zh_CN)"
)

// client is one session: its cookies, as the app's http jar is.
type client struct {
	http *http.Client
	mu   sync.Mutex
	jar  map[string]string
}

var (
	shared     *client
	sharedOnce sync.Once
)

// Shared returns the probe's one client, its cookies kept between calls.
func Shared() *client {
	sharedOnce.Do(func() {
		shared = &client{
			http: &http.Client{Timeout: 15 * time.Second},
			jar:  map[string]string{},
		}
	})
	return shared
}

var (
	deviceOnce sync.Once
	deviceID   string
)

// device returns this install's device ID, made once and kept: NetEase
// trusts a device it has seen before. The app keeps it in the user data
// directory; this keeps it in the cache directory, which iOS has.
func device() string {
	deviceOnce.Do(func() {
		const hexChars = "0123456789ABCDEF"
		make := func() string {
			b := make([]byte, 52)
			for i := range b {
				n, _ := rand.Int(rand.Reader, big.NewInt(16))
				b[i] = hexChars[n.Int64()]
			}
			return string(b)
		}
		path := ""
		if dir, err := os.UserCacheDir(); err == nil {
			path = filepath.Join(dir, "haruhikage-probe-device")
			if b, err := os.ReadFile(path); err == nil && len(b) == 52 {
				deviceID = string(b)
				return
			}
		}
		deviceID = make()
		if path != "" {
			os.MkdirAll(filepath.Dir(path), 0o700)
			os.WriteFile(path, []byte(deviceID), 0o600)
		}
	})
	return deviceID
}

// eapiEncrypt is the app's, line for line: the path, the JSON and an MD5 of
// the three are joined, then encrypted in ECB, and the hex is upper case.
func eapiEncrypt(path string, data any) (string, error) {
	text, err := json.Marshal(data)
	if err != nil {
		return "", err
	}
	digest := md5.Sum([]byte("nobody" + path + "use" + string(text) + "md5forencrypt"))
	plain := []byte(path + "-36cd479b6b5-" + string(text) + "-36cd479b6b5-" + hex.EncodeToString(digest[:]))
	block, err := aes.NewCipher([]byte(eapiKey))
	if err != nil {
		return "", err
	}
	pad := aes.BlockSize - len(plain)%aes.BlockSize
	plain = append(plain, bytes.Repeat([]byte{byte(pad)}, pad)...)
	out := make([]byte, len(plain))
	for i := 0; i < len(plain); i += aes.BlockSize {
		block.Encrypt(out[i:i+aes.BlockSize], plain[i:i+aes.BlockSize])
	}
	return strings.ToUpper(hex.EncodeToString(out)), nil
}

// eapiPost calls path through the eapi, as the app does, and returns the
// body it answered with.
func (c *client) eapiPost(path string, data map[string]any) ([]byte, error) {
	header := map[string]string{
		"osver":       "Microsoft-Windows-10-Professional-build-19045-64bit",
		"deviceId":    device(),
		"os":          "pc",
		"appver":      "3.1.17.204416",
		"versioncode": "140",
		"mobilename":  "",
		"buildver":    fmt.Sprint(time.Now().Unix()),
		"resolution":  "1920x1080",
		"channel":     "netease",
		"requestId":   fmt.Sprintf("%d_%04d", time.Now().UnixMilli(), time.Now().Nanosecond()%1000),
		"__csrf":      "",
	}
	c.mu.Lock()
	for k, v := range c.jar {
		switch k {
		case "MUSIC_U", "NMTID", "__csrf":
			header[k] = v
		}
	}
	c.mu.Unlock()

	data["header"] = header
	data["e_r"] = false

	params, err := eapiEncrypt(path, data)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequest("POST", eapiDomain+"/eapi/"+strings.TrimPrefix(path, "/api/"),
		strings.NewReader(url.Values{"params": {params}}.Encode()))
	if err != nil {
		return nil, err
	}
	var cookie []string
	for k, v := range header {
		cookie = append(cookie, url.QueryEscape(k)+"="+url.QueryEscape(v))
	}
	req.Header.Set("Cookie", strings.Join(cookie, "; "))
	req.Header.Set("User-Agent", eapiUA)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	res, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	for _, ck := range res.Cookies() {
		c.mu.Lock()
		c.jar[ck.Name] = ck.Value
		c.mu.Unlock()
	}
	if res.StatusCode != 200 {
		return nil, fmt.Errorf("%s: HTTP %d", path, res.StatusCode)
	}
	return io.ReadAll(res.Body)
}

// Search returns the names of songs matching q: the simplest real call the
// app makes, and enough to tell a working cipher from a broken one.
func Search(q string, limit int) ([]string, error) {
	if limit <= 0 {
		limit = 5
	}
	body, err := Shared().eapiPost("/api/search/get", map[string]any{
		"s": q, "type": 1, "limit": limit, "offset": 0, "total": "true",
	})
	if err != nil {
		return nil, err
	}
	var res struct {
		Code   int `json:"code"`
		Result struct {
			Songs []struct {
				Name string `json:"name"`
			} `json:"songs"`
		} `json:"result"`
	}
	if err := json.Unmarshal(body, &res); err != nil {
		return nil, fmt.Errorf("decode: %w (body %.120s)", err, body)
	}
	if res.Code != 200 {
		return nil, fmt.Errorf("code %d (body %.120s)", res.Code, body)
	}
	out := make([]string, 0, len(res.Result.Songs))
	for _, s := range res.Result.Songs {
		out = append(out, s.Name)
	}
	return out, nil
}
