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
