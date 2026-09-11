package bpz5

import (
	"bytes"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"strings"
	"sync"
	"time"
)

const (
	DefaultBaseURL    = "https://bpz5.com"
	DefaultClientName = "movie-search-frontend"
)

var (
	ErrNotConfigured = errors.New("bpz5 not configured")
	ErrEmptyTicket   = errors.New("ticket is required")
	ErrUpstream      = errors.New("bpz5 upstream error")
)

type Client struct {
	BaseURL    string
	Secret     string
	ClientName string
	HTTP       *http.Client

	mu            sync.Mutex
	anonymousID   string
	sessionReady  bool
}

func New(baseURL, secret string) *Client {
	base := strings.TrimRight(strings.TrimSpace(baseURL), "/")
	if base == "" {
		base = DefaultBaseURL
	}
	jar, _ := cookiejar.New(nil)
	return &Client{
		BaseURL:    base,
		Secret:     strings.TrimSpace(secret),
		ClientName: DefaultClientName,
		HTTP: &http.Client{
			Timeout: 40 * time.Second,
			Jar:     jar,
		},
	}
}

func (c *Client) Enabled() bool {
	return c != nil && c.Secret != ""
}

// NormalizeTicket accepts raw rpt1… or resolve://rpt1… (also from episode url).
func NormalizeTicket(ticket, fallbackURL string) string {
	t := strings.TrimSpace(ticket)
	if t == "" {
		t = strings.TrimSpace(fallbackURL)
	}
	t = strings.TrimPrefix(t, "resolve://")
	return strings.TrimSpace(t)
}

func SignHeaders(method, rawURL, secret, clientName string, now time.Time) (map[string]string, error) {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return nil, err
	}
	path := parsed.EscapedPath()
	if parsed.RawQuery != "" {
		path += "?" + parsed.RawQuery
	}
	ts := fmt.Sprintf("%d", now.UnixMilli())
	nonce := randomNonce()
	payload := method + "\n" + path + "\n" + ts + "\n" + nonce
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write([]byte(payload))
	sig := hex.EncodeToString(mac.Sum(nil))
	origin := parsed.Scheme + "://" + parsed.Host
	return map[string]string{
		"User-Agent":             "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
		"Accept":                 "application/json",
		"Origin":                 origin,
		"Referer":                origin + "/",
		"x-ai-movie-timestamp":   ts,
		"x-ai-movie-nonce":       nonce,
		"x-ai-movie-signature":   sig,
		"x-ai-movie-client-name": clientName,
	}, nil
}

func randomNonce() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(b[:])
}

func (c *Client) doJSON(method, path string, body any) (int, []byte, error) {
	if !c.Enabled() {
		return 0, nil, ErrNotConfigured
	}
	endpoint := c.BaseURL + path
	var reader io.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			return 0, nil, err
		}
		reader = bytes.NewReader(raw)
	}
	req, err := http.NewRequest(method, endpoint, reader)
	if err != nil {
		return 0, nil, err
	}
	headers, err := SignHeaders(method, endpoint, c.Secret, c.ClientName, time.Now())
	if err != nil {
		return 0, nil, err
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return resp.StatusCode, nil, err
	}
	return resp.StatusCode, raw, nil
}

type resolveLineResponse struct {
	Code string `json:"code"`
	Line *struct {
		URL     string `json:"url"`
		URLKind string `json:"url_kind"`
	} `json:"line"`
}

type ResolveResult struct {
	URL     string
	URLKind string
}

func (c *Client) ResolveLine(ticket string) (*ResolveResult, error) {
	ticket = NormalizeTicket(ticket, "")
	if ticket == "" {
		return nil, ErrEmptyTicket
	}
	_ = c.EnsureAnonymousSession(false)

	status, raw, err := c.doJSON(http.MethodPost, "/v1/playback/resolve-line", map[string]string{"ticket": ticket})
	if err != nil {
		return nil, err
	}
	if status == http.StatusUnauthorized {
		_ = c.EnsureAnonymousSession(true)
		status, raw, err = c.doJSON(http.MethodPost, "/v1/playback/resolve-line", map[string]string{"ticket": ticket})
		if err != nil {
			return nil, err
		}
	}
	if status != http.StatusOK && status != http.StatusCreated {
		return nil, fmt.Errorf("%w: HTTP %d: %s", ErrUpstream, status, truncate(string(raw), 200))
	}
	var parsed resolveLineResponse
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return nil, fmt.Errorf("%w: invalid json", ErrUpstream)
	}
	if parsed.Line == nil || strings.TrimSpace(parsed.Line.URL) == "" {
		return nil, fmt.Errorf("%w: missing line.url", ErrUpstream)
	}
	return &ResolveResult{
		URL:     strings.TrimSpace(parsed.Line.URL),
		URLKind: parsed.Line.URLKind,
	}, nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}
