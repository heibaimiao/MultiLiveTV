package merge

import (
	"strconv"
	"testing"

	"github.com/heibaimiao/multilivetv/api-go/internal/config"
	"github.com/heibaimiao/multilivetv/api-go/internal/model"
)

func TestNormalizeVodTitle(t *testing.T) {
	cases := map[string]string{
		"鲨笼绝境":   "鲨笼绝境",
		" 鲨笼绝境 ": "鲨笼绝境",
		"Shark Bait": "sharkbait",
	}
	for input, want := range cases {
		got := NormalizeVodTitle(input)
		if got != want {
			t.Errorf("NormalizeVodTitle(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestBuildVodMergeKey_OnlyByName(t *testing.T) {
	a := model.VodItem{VodName: "鲨笼绝境", TypeName: "动作片"}
	b := model.VodItem{VodName: "鲨笼绝境", TypeName: "恐怖片"}
	if BuildVodMergeKey(a) != BuildVodMergeKey(b) {
		t.Fatal("same title should merge regardless of type_name")
	}
}

func TestMergeVodItems_SharkBait(t *testing.T) {
	store := config.NewEmptySourceStore()
	items := make([]model.MergeableVodItem, 0, 10)
	for i := 1; i <= 10; i++ {
		items = append(items, model.MergeableVodItem{
			VodItem: model.VodItem{
				VodID:    strconv.Itoa(i),
				VodName:  "鲨笼绝境",
				TypeName: []string{"动作片", "恐怖片", "惊悚片"}[i%3],
			},
			SourceID:   i,
			SourceName: "源" + strconv.Itoa(i),
		})
	}
	merged := MergeVodItems(items, store)
	if len(merged) != 1 {
		t.Fatalf("expected 1 merged item, got %d", len(merged))
	}
	if len(merged[0].Variants) != 10 {
		t.Fatalf("expected 10 variants, got %d", len(merged[0].Variants))
	}
}

func TestMergeVodItems_DifferentTitles(t *testing.T) {
	store := config.NewEmptySourceStore()
	items := []model.MergeableVodItem{
		{VodItem: model.VodItem{VodName: "电影A", VodID: "1"}, SourceID: 1, SourceName: "s1"},
		{VodItem: model.VodItem{VodName: "电影B", VodID: "2"}, SourceID: 2, SourceName: "s2"},
	}
	merged := MergeVodItems(items, store)
	if len(merged) != 2 {
		t.Fatalf("expected 2 items, got %d", len(merged))
	}
}

func TestSortMergedByUpdatedDesc(t *testing.T) {
	store := config.NewEmptySourceStore()
	items := []model.MergeableVodItem{
		{
			VodItem:    model.VodItem{VodID: "1", VodName: "旧片", VodTime: 100},
			SourceID:   1,
			SourceName: "s1",
		},
		{
			VodItem:    model.VodItem{VodID: "2", VodName: "新片", VodTime: 300},
			SourceID:   1,
			SourceName: "s1",
		},
		{
			VodItem:    model.VodItem{VodID: "3", VodName: "新片", VodTime: 200},
			SourceID:   2,
			SourceName: "s2",
		},
	}
	merged := SortMergedByUpdatedDesc(MergeVodItems(items, store))
	if len(merged) != 2 {
		t.Fatalf("expected 2 merged, got %d", len(merged))
	}
	if merged[0].VodName != "新片" {
		t.Fatalf("expected 新片 first, got %s", merged[0].VodName)
	}
	if merged[0].VodTime != 300 {
		t.Fatalf("expected latest group time 300, got %d", merged[0].VodTime)
	}
	if merged[0].VodTime < merged[1].VodTime {
		t.Fatal("list should be time-desc when years are equal/empty")
	}
}

func TestSortMergedPrefersReleaseYear(t *testing.T) {
	items := []model.MergedVodItem{
		{VodItem: model.VodItem{VodID: "1", VodName: "旧年新更", VodYear: "2020", VodTime: 900}},
		{VodItem: model.VodItem{VodID: "2", VodName: "新年旧更", VodYear: "2026", VodTime: 100}},
		{VodItem: model.VodItem{VodID: "3", VodName: "无年份", VodTime: 999}},
	}
	sorted := SortMergedByUpdatedDesc(items)
	if sorted[0].VodID != "2" || sorted[1].VodID != "1" || sorted[2].VodID != "3" {
		t.Fatalf("year-first order wrong: %#v", []string{sorted[0].VodID, sorted[1].VodID, sorted[2].VodID})
	}
}

func TestMergeFoldsEmptyYearIntoConcreteYear(t *testing.T) {
	store := config.NewEmptySourceStore()
	items := []model.MergeableVodItem{
		{VodItem: model.VodItem{VodID: "1", VodName: "热血部落", VodYear: "", VodTime: 100}, SourceID: 1, SourceName: "a"},
		{VodItem: model.VodItem{VodID: "2", VodName: "热血部落", VodYear: "2024", VodTime: 200}, SourceID: 2, SourceName: "b"},
	}
	merged := MergeVodItems(items, store)
	if len(merged) != 1 {
		t.Fatalf("expected 1 merged item, got %d", len(merged))
	}
	if merged[0].VodTime != 200 {
		t.Fatalf("expected latest time 200, got %d", merged[0].VodTime)
	}
	if len(merged[0].Variants) != 2 {
		t.Fatalf("expected 2 variants, got %d", len(merged[0].Variants))
	}
}

func TestMergeKeepsDistinctYearsSeparate(t *testing.T) {
	store := config.NewEmptySourceStore()
	items := []model.MergeableVodItem{
		{VodItem: model.VodItem{VodID: "1", VodName: "兄弟", VodYear: "2007", VodTime: 100}, SourceID: 1, SourceName: "a"},
		{VodItem: model.VodItem{VodID: "2", VodName: "兄弟", VodYear: "2009", VodTime: 200}, SourceID: 1, SourceName: "a"},
		{VodItem: model.VodItem{VodID: "3", VodName: "兄弟", VodYear: "", VodTime: 300}, SourceID: 1, SourceName: "a"},
	}
	merged := SortMergedByUpdatedDesc(MergeVodItems(items, store))
	if len(merged) != 2 {
		t.Fatalf("expected 2 items, got %d", len(merged))
	}
}

func TestNormalizeVodYearRejectsFuturePlaceholder(t *testing.T) {
	if got := NormalizeVodYear("2030"); got != "" {
		t.Fatalf("expected empty for 2030, got %q", got)
	}
	if got := NormalizeVodYear("1899"); got != "" {
		t.Fatalf("expected empty for 1899, got %q", got)
	}
	current := maxPlausibleReleaseYear() - 1
	if got := NormalizeVodYear(strconv.Itoa(current)); got != strconv.Itoa(current) {
		t.Fatalf("current year should stay, got %q", got)
	}
	if got := NormalizeVodYear(strconv.Itoa(current + 2)); got != "" {
		t.Fatalf("year+2 should drop, got %q", got)
	}
}

func TestSortMergedDropsFuturePlaceholderYear(t *testing.T) {
	items := []model.MergedVodItem{
		{VodItem: model.VodItem{VodID: "1", VodName: "脏年份", VodYear: "2030", VodTime: 1_700_000_000}},
		{VodItem: model.VodItem{VodID: "2", VodName: "老片", VodYear: "2020", VodTime: 1_600_000_000}},
	}
	sorted := SortMergedByUpdatedDesc(items)
	if sorted[0].VodID != "1" {
		t.Fatalf("recent placeholder-year title should stay near top, got %s", sorted[0].VodID)
	}
	if NormalizeVodYear("2030") != "" {
		t.Fatal("2030 must not display as release year")
	}
}

func TestIsCompatibleVodMatch(t *testing.T) {
	primary := model.VodItem{VodName: "兄弟", VodYear: "2009"}
	if !IsCompatibleVodMatch(primary, model.VodItem{VodName: "兄弟", VodYear: ""}) {
		t.Fatal("empty year should match")
	}
	if IsCompatibleVodMatch(primary, model.VodItem{VodName: "兄弟", VodYear: "2007"}) {
		t.Fatal("different years must not match")
	}
}
