package parser

import (
	"encoding/json"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"

	"github.com/heibaimiao/multilivetv/api-go/internal/model"
)

type WeightTable struct {
	Version       int            `json:"version"`
	DefaultWeight int            `json:"defaultWeight"`
	ByPlayFrom    map[string]int `json:"byPlayFrom"`
	ByProviderID  map[string]int `json:"byProviderId"`
	BySourceID    map[string]int `json:"bySourceId"`
}

var (
	weightsMu sync.RWMutex
	weights   = defaultWeightTable()
)

func defaultWeightTable() WeightTable {
	return WeightTable{
		Version:       2,
		DefaultWeight: 100,
		ByPlayFrom: map[string]int{
			"huo":           1000,
			"lv2":           999,
			"rrys":          995,
			"bytedance":     990,
			"dong":          985,
			"cloudflare":    950,
			"cloudflare-4k": 940,
			"qq":            910,
			"qiyi":          900,
			"youku":         870,
			"mgtv":          860,
			"bilibili":      850,
			"hnm3u8":        920,
			"xlm3u8":        900,
			"lzm3u8":        760,
		},
		ByProviderID: map[string]int{
			"official-v":             1000,
			"bytevod-lv2":            999,
			"official-r":             995,
			"bytedance":              990,
			"dong":                   985,
			"bytevod-cloudflare":     950,
			"bytevod-cloudflare-4k":  940,
			"official-hot-playback":  910,
		},
		BySourceID: map[string]int{},
	}
}

func LoadWeightsFile(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	var table WeightTable
	if err := json.Unmarshal(data, &table); err != nil {
		return err
	}
	if table.DefaultWeight == 0 {
		table.DefaultWeight = 100
	}
	if table.ByPlayFrom == nil {
		table.ByPlayFrom = map[string]int{}
	}
	if table.ByProviderID == nil {
		table.ByProviderID = map[string]int{}
	}
	if table.BySourceID == nil {
		table.BySourceID = map[string]int{}
	}
	weightsMu.Lock()
	weights = table
	weightsMu.Unlock()
	return nil
}

func CurrentWeights() WeightTable {
	weightsMu.RLock()
	defer weightsMu.RUnlock()
	return weights
}

// WeightFor: providerId > playFrom > sourceId > default.
func WeightFor(playFrom, providerID string, sourceID int) int {
	weightsMu.RLock()
	defer weightsMu.RUnlock()
	providerID = strings.ToLower(strings.TrimSpace(providerID))
	playFrom = strings.ToLower(strings.TrimSpace(playFrom))
	if providerID != "" {
		if w, ok := weights.ByProviderID[providerID]; ok {
			return w
		}
	}
	if playFrom != "" {
		if w, ok := weights.ByPlayFrom[playFrom]; ok {
			return w
		}
	}
	if sourceID != 0 {
		if w, ok := weights.BySourceID[strconv.Itoa(sourceID)]; ok {
			return w
		}
	}
	return weights.DefaultWeight
}

// SourceWeight returns bySourceId weight (for list primary / variants).
func SourceWeight(sourceID int) int {
	return WeightFor("", "", sourceID)
}

var directMediaRE = regexp.MustCompile(`(?i)\.(m3u8|mp4|mkv|flv|mov)(\?|$|#)`)

func playabilityScore(source model.PlaySource) int {
	n := 0
	for _, ep := range source.Episodes {
		if directMediaRE.MatchString(ep.URL) {
			n++
		}
	}
	return n
}

func SortPlaySources(sources []model.PlaySource) {
	sort.SliceStable(sources, func(i, j int) bool {
		a, b := sources[i], sources[j]
		if a.Weight != b.Weight {
			return a.Weight > b.Weight
		}
		sa, sb := playabilityScore(a), playabilityScore(b)
		if sa != sb {
			return sa > sb
		}
		return len(a.Episodes) > len(b.Episodes)
	})
}

func AnnotatePlaySource(source model.PlaySource, rawPlayFrom string) model.PlaySource {
	playFrom := strings.TrimSpace(rawPlayFrom)
	if playFrom == "" {
		playFrom = source.PlayFrom
	}
	if playFrom == "" {
		playFrom = source.Key
	}
	source.PlayFrom = playFrom
	if source.Mode == "" {
		source.Mode = "direct"
	}
	// Preserve explicit upstream weight (e.g. bpz5 preference_weight) when already set > 0
	// and higher than table — callers set Weight before annotate for official lines.
	tableW := WeightFor(source.PlayFrom, source.ProviderID, source.SourceID)
	if source.Weight <= 0 {
		source.Weight = tableW
	}
	return source
}
