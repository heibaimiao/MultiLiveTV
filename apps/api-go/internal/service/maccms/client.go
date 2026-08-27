package maccms

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

func normalizeBaseURL(raw string) string {
	if strings.HasSuffix(raw, "/") {
		return raw
	}
	return raw + "/"
}

func fetchBody(baseURL string, params map[string]string) ([]byte, error) {
	u, err := url.Parse(normalizeBaseURL(baseURL))
	if err != nil {
		return nil, err
	}
	q := u.Query()
	for k, v := range params {
		q.Set(k, v)
	}
	u.RawQuery = q.Encode()

	req, err := http.NewRequest(http.MethodGet, u.String(), nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", userAgent)

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("MacCMS request failed: %d", resp.StatusCode)
	}
	return io.ReadAll(resp.Body)
}

func FetchVodTypes(source model.Source) ([]model.VodType, error) {
	body, err := fetchBody(source.URL, map[string]string{"ac": "list", "pg": "1"})
	if err != nil {
		return nil, err
	}
	var data model.MacCmsListResponse
	if err := json.Unmarshal(body, &data); err != nil {
		// class field may have list with vod_id as number
		parsed, perr := model.ParseMacCmsListResponse(body)
		if perr != nil {
			return nil, err
		}
		return parsed.Class, nil
	}
	return data.Class, nil
}

func FetchVodList(source model.Source, page int, typeID *int) (*model.MacCmsListResponse, error) {
	params := map[string]string{"ac": "list", "pg": fmt.Sprintf("%d", page)}
	if typeID != nil {
		params["t"] = fmt.Sprintf("%d", *typeID)
	}
	body, err := fetchBody(source.URL, params)
	if err != nil {
		return nil, err
	}
	return model.ParseMacCmsListResponse(body)
}

func FetchVodDetail(source model.Source, ids string) (*model.MacCmsDetailResponse, error) {
	body, err := fetchBody(source.URL, map[string]string{"ac": "detail", "ids": ids})
	if err != nil {
		return nil, err
	}
	return model.ParseMacCmsDetailResponse(body)
}

func SearchVod(source model.Source, keyword string, page int) (*model.MacCmsListResponse, error) {
	params := map[string]string{
		"ac": "list",
		"wd": keyword,
		"pg": fmt.Sprintf("%d", page),
	}
	body, err := fetchBody(source.URL, params)
	if err != nil {
		return nil, err
	}
	return model.ParseMacCmsListResponse(body)
}
