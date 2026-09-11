package parser

import (
	"path/filepath"
	"runtime"
	"testing"

	"github.com/heibaimiao/multilivetv/api-go/internal/model"
)

func TestWeightOrderMatchesSpec(t *testing.T) {
	table := defaultWeightTable()
	weightsMu.Lock()
	weights = table
	weightsMu.Unlock()

	ordered := []struct {
		playFrom string
		want     int
	}{
		{"huo", 1000},
		{"lv2", 999},
		{"cloudflare", 950},
		{"cloudflare-4k", 940},
		{"hnm3u8", 920},
		{"qq", 910},
		{"unknown", 100},
	}
	prev := 1 << 30
	for _, row := range ordered {
		w := WeightFor(row.playFrom, "", 0)
		if w != row.want {
			t.Fatalf("%s: got %d want %d", row.playFrom, w, row.want)
		}
		if w > prev {
			t.Fatalf("%s weight %d should not exceed previous %d", row.playFrom, w, prev)
		}
		prev = w
	}
}

func TestWeightPrefersProviderId(t *testing.T) {
	weightsMu.Lock()
	weights = defaultWeightTable()
	weightsMu.Unlock()

	w := WeightFor("hnm3u8", "bytevod-cloudflare-4k", 0)
	if w != 940 {
		t.Fatalf("provider should win: got %d", w)
	}
}

func TestWeightFallsBackToSourceId(t *testing.T) {
	weightsMu.Lock()
	weights = WeightTable{
		DefaultWeight: 100,
		ByPlayFrom:    map[string]int{},
		ByProviderID:  map[string]int{},
		BySourceID:    map[string]int{"125": 470},
	}
	weightsMu.Unlock()

	w := WeightFor("unknownm3u8", "", 125)
	if w != 470 {
		t.Fatalf("sourceId fallback: got %d", w)
	}
}

func TestSortPlaySourcesByWeightThenPlayability(t *testing.T) {
	weightsMu.Lock()
	weights = defaultWeightTable()
	weightsMu.Unlock()

	sources := []model.PlaySource{
		{Key: "hn", Name: "红牛", PlayFrom: "hnm3u8", Weight: WeightFor("hnm3u8", "", 0), Mode: "direct", Episodes: []model.Episode{{Name: "1", URL: "https://a.com/a.m3u8"}}},
		{Key: "qq", Name: "腾讯", PlayFrom: "qq", Weight: WeightFor("qq", "", 0), Mode: "ticket", Episodes: []model.Episode{{Name: "1", URL: "resolve://x"}}},
		{Key: "c4k", Name: "4K", PlayFrom: "cloudflare-4k", Weight: WeightFor("cloudflare-4k", "", 0), Mode: "ticket", Episodes: []model.Episode{{Name: "1", URL: "resolve://y"}}},
		{Key: "huo", Name: "官方V", PlayFrom: "huo", Weight: WeightFor("huo", "", 0), Mode: "ticket", Episodes: []model.Episode{{Name: "1", URL: "resolve://z"}}},
	}
	SortPlaySources(sources)
	want := []string{"huo", "c4k", "hn", "qq"}
	for i, k := range want {
		if sources[i].Key != k {
			t.Fatalf("index %d: got %s want %s (full=%v)", i, sources[i].Key, k, keys(sources))
		}
	}
}

func TestLoadWeightsFile(t *testing.T) {
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("caller")
	}
	path := filepath.Join(filepath.Dir(file), "..", "..", "..", "config", "play-line-weights.json")
	if err := LoadWeightsFile(path); err != nil {
		t.Fatal(err)
	}
	if WeightFor("huo", "", 0) != 1000 {
		t.Fatalf("loaded huo weight=%d", WeightFor("huo", "", 0))
	}
	if WeightFor("", "", 125) != 470 {
		t.Fatalf("loaded source 125 weight=%d", WeightFor("", "", 125))
	}
}

func keys(sources []model.PlaySource) []string {
	out := make([]string, len(sources))
	for i, s := range sources {
		out[i] = s.Key
	}
	return out
}
