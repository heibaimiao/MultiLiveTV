package bpz5

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

type CatalogCard struct {
	ID                 string `json:"id"`
	Title              string `json:"title"`
	Year               any    `json:"year"`
	SelectedVariantID  string `json:"selected_variant_id"`
	DefaultVariantID   string `json:"default_variant_id"`
	AvailableEpisodeCount any `json:"available_episode_count"`
	HasPlayback        *bool  `json:"has_playback"`
}

type Episode struct {
	Token  string `json:"token"`
	Title  string `json:"title"`
	Number int    `json:"number"`
}

type LineOption struct {
	ProviderID        string `json:"provider_id"`
	ProviderName      string `json:"provider_name"`
	Label             string `json:"label"`
	PlayFrom          string `json:"play_from"`
	URL               string `json:"url"`
	URLKind           string `json:"url_kind"`
	ResolveMode       string `json:"resolve_mode"`
	ResolveRequired   bool   `json:"resolve_required"`
	Resolved          bool   `json:"resolved"`
	PreferenceWeight  int    `json:"preference_weight"`
}

func (c *Client) SearchCatalog(query string, limit int) ([]CatalogCard, error) {
	if limit <= 0 {
		limit = 10
	}
	q := url.Values{}
	q.Set("page", "1")
	q.Set("limit", strconv.Itoa(limit))
	q.Set("intent", "catalog_search")
	q.Set("q", strings.TrimSpace(query))
	status, raw, err := c.doJSON(http.MethodGet, "/v1/browse/catalog?"+q.Encode(), nil)
	if err != nil {
		return nil, err
	}
	if status != http.StatusOK {
		return nil, fmt.Errorf("%w: catalog HTTP %d", ErrUpstream, status)
	}
	var payload struct {
		Cards []CatalogCard `json:"cards"`
	}
	if err := json.Unmarshal(raw, &payload); err != nil {
		return nil, err
	}
	return payload.Cards, nil
}

func (card CatalogCard) VariantID() string {
	if card.SelectedVariantID != "" {
		return card.SelectedVariantID
	}
	if card.DefaultVariantID != "" {
		return card.DefaultVariantID
	}
	return card.ID
}

func (card CatalogCard) YearString() string {
	switch v := card.Year.(type) {
	case string:
		return strings.TrimSpace(v)
	case float64:
		if v > 0 {
			return strconv.Itoa(int(v))
		}
	case json.Number:
		return v.String()
	}
	return ""
}

func (c *Client) FetchEpisodes(variantID string, limit int) ([]Episode, error) {
	if limit <= 0 {
		limit = 40
	}
	path := "/v1/catalog/" + url.PathEscape(variantID) + "/episodes?offset=0&limit=" + strconv.Itoa(limit)
	status, raw, err := c.doJSON(http.MethodGet, path, nil)
	if err != nil {
		return nil, err
	}
	if status != http.StatusOK {
		return nil, fmt.Errorf("%w: episodes HTTP %d", ErrUpstream, status)
	}
	var payload struct {
		Episodes []Episode `json:"episodes"`
	}
	if err := json.Unmarshal(raw, &payload); err != nil {
		return nil, err
	}
	return payload.Episodes, nil
}

func (c *Client) PlaybackResolve(episodeToken string) ([]LineOption, error) {
	token := strings.TrimSpace(episodeToken)
	if token == "" {
		return nil, ErrEmptyTicket
	}
	path := "/v1/playback/resolve/" + url.PathEscape(token)
	status, raw, err := c.doJSON(http.MethodGet, path, nil)
	if err != nil {
		return nil, err
	}
	if status != http.StatusOK {
		return nil, fmt.Errorf("%w: playback resolve HTTP %d", ErrUpstream, status)
	}
	var payload struct {
		LineOptions []LineOption `json:"line_options"`
	}
	if err := json.Unmarshal(raw, &payload); err != nil {
		return nil, err
	}
	return payload.LineOptions, nil
}

func IsOfficialParseLine(line LineOption) bool {
	if line.ResolveMode == "parse" {
		return true
	}
	if line.URLKind == "resolve_ticket" {
		return true
	}
	if line.ResolveRequired && strings.HasPrefix(strings.TrimSpace(line.URL), "resolve://") {
		return true
	}
	return false
}
