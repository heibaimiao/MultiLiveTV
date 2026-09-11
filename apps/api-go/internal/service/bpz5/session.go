package bpz5

import (
	"encoding/json"
	"net/http"
)

func (c *Client) EnsureAnonymousSession(force bool) error {
	if !c.Enabled() {
		return ErrNotConfigured
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.sessionReady && !force {
		return nil
	}
	if c.anonymousID == "" {
		c.anonymousID = randomNonce()
	}
	status, raw, err := c.doJSONUnlocked(http.MethodPost, "/v1/users/anonymous", map[string]string{
		"anonymous_id": c.anonymousID,
	})
	if err != nil {
		c.sessionReady = false
		return err
	}
	if status >= 400 {
		c.sessionReady = false
		return ErrUpstream
	}
	var parsed map[string]any
	_ = json.Unmarshal(raw, &parsed)
	c.sessionReady = true
	return nil
}

// doJSONUnlocked is used while c.mu is held for session bootstrap.
func (c *Client) doJSONUnlocked(method, path string, body any) (int, []byte, error) {
	return c.doJSON(method, path, body)
}
