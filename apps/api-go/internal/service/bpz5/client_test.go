package bpz5

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/heibaimiao/multilivetv/api-go/internal/model"
)

func TestNormalizeTicket(t *testing.T) {
	cases := []struct {
		ticket, url, want string
	}{
		{"rpt1.abc", "", "rpt1.abc"},
		{"", "resolve://rpt1.abc", "rpt1.abc"},
		{"  resolve://rpt1.x  ", "ignored", "rpt1.x"},
	}
	for _, c := range cases {
		got := NormalizeTicket(c.ticket, c.url)
		if got != c.want {
			t.Fatalf("NormalizeTicket(%q,%q)=%q want %q", c.ticket, c.url, got, c.want)
		}
	}
}

func TestSignHeadersPayloadShape(t *testing.T) {
	now := time.UnixMilli(1730000000000)
	headers, err := SignHeaders("POST", "https://bpz5.com/v1/playback/resolve-line", "secret", DefaultClientName, now)
	if err != nil {
		t.Fatal(err)
	}
	nonce := headers["x-ai-movie-nonce"]
	payload := "POST\n/v1/playback/resolve-line\n1730000000000\n" + nonce
	mac := hmac.New(sha256.New, []byte("secret"))
	_, _ = mac.Write([]byte(payload))
	want := hex.EncodeToString(mac.Sum(nil))
	if headers["x-ai-movie-signature"] != want {
		t.Fatalf("sig mismatch")
	}
}

func TestPickBestCardExactTitle(t *testing.T) {
	cards := []CatalogCard{
		{ID: "a", Title: "花开锦绣2", Year: "2024"},
		{ID: "b", Title: "花开锦绣", Year: "2023", SelectedVariantID: "var-b"},
	}
	best, score := PickBestCard("花开锦绣", "2023", cards)
	if best == nil || best.ID != "b" {
		t.Fatalf("best=%v score=%d", best, score)
	}
	if score < matchScoreThreshold {
		t.Fatalf("score=%d", score)
	}
}

func TestPickBestCardRejectsWeakMatch(t *testing.T) {
	cards := []CatalogCard{{ID: "a", Title: "完全无关的片子", Year: "2020"}}
	best, score := PickBestCard("花开锦绣", "", cards)
	if score >= matchScoreThreshold {
		t.Fatalf("unexpected accept best=%v score=%d", best, score)
	}
}

func TestEnrichOfficialPlaySources(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/v1/users/anonymous":
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"user":{"id":"u1","display_name":"anon"}}`))
		case r.URL.Path == "/v1/browse/catalog":
			_, _ = w.Write([]byte(`{"cards":[{"id":"v1","title":"测试片","year":"2024","selected_variant_id":"v1"}]}`))
		case strings.HasSuffix(r.URL.Path, "/episodes"):
			_, _ = w.Write([]byte(`{"episodes":[{"token":"YJ-aaa","title":"第1集","number":1}]}`))
		case strings.HasPrefix(r.URL.Path, "/v1/playback/resolve/"):
			_, _ = w.Write([]byte(`{"line_options":[
			  {"provider_id":"bytevod-cloudflare","provider_name":"高清-官方C","play_from":"cloudflare","url":"resolve://rpt1.abc","url_kind":"resolve_ticket","resolve_mode":"parse","resolve_required":true},
			  {"provider_id":"hongniu","provider_name":"红牛","play_from":"hnm3u8","url":"https://cdn.example/a.m3u8","url_kind":"m3u8","resolve_mode":"direct","resolved":true}
			]}`))
		case r.URL.Path == "/v1/playback/resolve-line":
			w.WriteHeader(http.StatusCreated)
			_, _ = w.Write([]byte(`{"line":{"url":"https://cdn.example/ok.m3u8","url_kind":"m3u8"}}`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()

	c := New(srv.URL, "secret")
	c.HTTP = srv.Client()
	sources := c.EnrichOfficialPlaySources(
		model.VodItem{VodName: "测试片", VodYear: "2024"},
		[]model.PlaySource{{Name: "红牛", Key: "hn", Episodes: []model.Episode{{Name: "第1集", URL: "https://x"}}}},
	)
	if len(sources) != 1 {
		t.Fatalf("sources=%d %#v", len(sources), sources)
	}
	if sources[0].Key != "bpz5:bytevod-cloudflare:cloudflare" {
		t.Fatalf("key=%s", sources[0].Key)
	}
	if sources[0].Mode != "ticket" {
		t.Fatalf("mode=%s", sources[0].Mode)
	}
	if !strings.HasPrefix(sources[0].Episodes[0].URL, "resolve://") {
		t.Fatalf("ep url=%s", sources[0].Episodes[0].URL)
	}
}

func TestEnrichSplitsOfficialHotPlaybackByPlayFrom(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/v1/users/anonymous":
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"user":{"id":"u1"}}`))
		case r.URL.Path == "/v1/browse/catalog":
			_, _ = w.Write([]byte(`{"cards":[{"id":"v1","title":"测试片","year":"2024","selected_variant_id":"v1"}]}`))
		case strings.HasSuffix(r.URL.Path, "/episodes"):
			_, _ = w.Write([]byte(`{"episodes":[{"token":"YJ-aaa","title":"正片","number":1}]}`))
		case strings.HasPrefix(r.URL.Path, "/v1/playback/resolve/"):
			_, _ = w.Write([]byte(`{"line_options":[
			  {"provider_id":"official-hot-playback","provider_name":"腾讯视频","play_from":"qq","url":"resolve://rpt1.qq","url_kind":"resolve_ticket","resolve_mode":"parse"},
			  {"provider_id":"official-hot-playback","provider_name":"爱奇艺","play_from":"qiyi","url":"resolve://rpt1.qiyi","url_kind":"resolve_ticket","resolve_mode":"parse"},
			  {"provider_id":"dong","provider_name":"1080P-官方D","play_from":"Dong","url":"resolve://rpt1.dong","url_kind":"resolve_ticket","resolve_mode":"parse"}
			]}`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()

	c := New(srv.URL, "secret")
	c.HTTP = srv.Client()
	sources := c.EnrichOfficialPlaySources(
		model.VodItem{VodName: "测试片", VodYear: "2024"},
		nil,
	)
	if len(sources) != 3 {
		t.Fatalf("sources=%d %#v", len(sources), sources)
	}
	keys := map[string]bool{}
	for _, s := range sources {
		keys[s.Key] = true
	}
	for _, want := range []string{
		"bpz5:official-hot-playback:qq",
		"bpz5:official-hot-playback:qiyi",
		"bpz5:dong:Dong",
	} {
		if !keys[want] {
			t.Fatalf("missing key %s in %#v", want, keys)
		}
	}
}

func TestResolveLineSuccess(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/v1/users/anonymous" {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"user":{"id":"u1"}}`))
			return
		}
		if r.URL.Path != "/v1/playback/resolve-line" {
			t.Fatalf("path = %s", r.URL.Path)
		}
		var body map[string]string
		_ = json.NewDecoder(r.Body).Decode(&body)
		if !strings.HasPrefix(body["ticket"], "rpt1.") {
			t.Fatalf("ticket = %v", body)
		}
		w.WriteHeader(http.StatusCreated)
		_, _ = w.Write([]byte(`{"line":{"url":"https://cdn.example/index.m3u8","url_kind":"m3u8"}}`))
	}))
	defer srv.Close()

	c := New(srv.URL, "test-secret")
	c.HTTP = srv.Client()
	res, err := c.ResolveLine("resolve://rpt1.eyJ.test")
	if err != nil {
		t.Fatal(err)
	}
	if res.URL != "https://cdn.example/index.m3u8" {
		t.Fatalf("url = %s", res.URL)
	}
}

func TestResolveLineNotConfigured(t *testing.T) {
	c := New("", "")
	_, err := c.ResolveLine("rpt1.x")
	if err != ErrEmptyTicket && err != ErrNotConfigured {
		// empty secret → EnsureAnonymous fails NotConfigured; ticket normalize still runs first
		if err != ErrNotConfigured {
			t.Fatalf("err = %v", err)
		}
	}
}
