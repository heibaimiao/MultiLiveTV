package parser

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/heibaimiao/multilivetv/api-go/internal/model"
)

const userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

var httpClient = &http.Client{Timeout: 15 * time.Second}

func splitPlayFrom(vodPlayFrom string) []string {
	if vodPlayFrom == "" {
		return nil
	}
	if strings.Contains(vodPlayFrom, "$$$") {
		return filterEmpty(strings.Split(vodPlayFrom, "$$$"))
	}
	if strings.Contains(vodPlayFrom, ",") {
		return filterEmpty(strings.Split(vodPlayFrom, ","))
	}
	return []string{vodPlayFrom}
}

func filterEmpty(parts []string) []string {
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

func ParsePlayURL(vodPlayFrom, vodPlayURL string) []model.PlaySource {
	if vodPlayFrom == "" || vodPlayURL == "" {
		return nil
	}

	fromList := splitPlayFrom(vodPlayFrom)
	var urlList []string
	if strings.Contains(vodPlayURL, "$$$") {
		urlList = strings.Split(vodPlayURL, "$$$")
	} else {
		urlList = []string{vodPlayURL}
	}

	sources := make([]model.PlaySource, 0, len(fromList))
	for i, name := range fromList {
		rawEpisodes := ""
		if i < len(urlList) {
			rawEpisodes = urlList[i]
		} else if len(urlList) > 0 {
			rawEpisodes = urlList[0]
		}

		episodes := make([]model.Episode, 0)
		for _, item := range strings.Split(rawEpisodes, "#") {
			if item == "" {
				continue
			}
			dollarIndex := strings.Index(item, "$")
			if dollarIndex == -1 {
				episodes = append(episodes, model.Episode{Name: "第" + item, URL: item})
			} else {
				epName := item[:dollarIndex]
				if epName == "" {
					epName = "播放"
				}
				episodes = append(episodes, model.Episode{Name: epName, URL: item[dollarIndex+1:]})
			}
		}

		key := strings.TrimSpace(name)
		if key == "" {
			key = fmt.Sprintf("line-%d", i+1)
		}
		sources = append(sources, model.PlaySource{
			Name:     FormatPlaySourceName(name, i),
			Key:      key,
			Episodes: episodes,
		})
	}
	return sources
}

type VodWithSource struct {
	Source model.Source
	Vod    model.VodItem
}

func MergePlaySourcesFromVods(entries []VodWithSource) []model.PlaySource {
	merged := make(map[string]model.PlaySource)

	for _, entry := range entries {
		parsed := ParsePlayURL(entry.Vod.VodPlayFrom, entry.Vod.VodPlayURL)
		for _, line := range parsed {
			key := fmt.Sprintf("%d:%s", entry.Source.ID, line.Key)
			name := entry.Source.Name + " · " + line.Name
			existing, ok := merged[key]
			if !ok || len(line.Episodes) > len(existing.Episodes) {
				merged[key] = model.PlaySource{
					Name:     name,
					Key:      key,
					Episodes: line.Episodes,
					SourceID: entry.Source.ID,
				}
			}
		}
	}

	out := make([]model.PlaySource, 0, len(merged))
	for _, v := range merged {
		out = append(out, v)
	}
	return out
}

func ParsePlayAddress(source model.Source, playURL string) model.ParseResult {
	if source.JxURL == "" {
		return model.ParseResult{URL: playURL, Parsed: false}
	}

	parseEndpoint := source.JxURL + url.QueryEscape(playURL)
	req, err := http.NewRequest(http.MethodGet, parseEndpoint, nil)
	if err != nil {
		return model.ParseResult{URL: playURL, Parsed: false}
	}
	req.Header.Set("User-Agent", userAgent)

	resp, err := httpClient.Do(req)
	if err != nil {
		return model.ParseResult{URL: playURL, Parsed: false}
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return model.ParseResult{URL: playURL, Parsed: false}
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return model.ParseResult{URL: playURL, Parsed: false}
	}

	contentType := resp.Header.Get("Content-Type")
	if strings.Contains(contentType, "application/json") {
		var data any
		if json.Unmarshal(body, &data) == nil {
			if s, ok := data.(string); ok && strings.HasPrefix(s, "http") {
				return model.ParseResult{URL: strings.TrimSpace(s), Parsed: true}
			}
			if m, ok := data.(map[string]any); ok {
				if u, ok := m["url"].(string); ok {
					return model.ParseResult{URL: u, Parsed: true}
				}
				if d, ok := m["data"].(map[string]any); ok {
					if u, ok := d["url"].(string); ok {
						return model.ParseResult{URL: u, Parsed: true}
					}
				}
			}
		}
	} else {
		text := strings.TrimSpace(string(body))
		if strings.HasPrefix(text, "http") {
			return model.ParseResult{URL: text, Parsed: true}
		}
	}

	return model.ParseResult{URL: playURL, Parsed: false}
}
