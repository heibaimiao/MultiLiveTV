package merge

import (
	"regexp"
	"strconv"
	"strings"

	"github.com/heibaimiao/multilivetv/api-go/internal/config"
	"github.com/heibaimiao/multilivetv/api-go/internal/model"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/maccms"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/parser"
)

const maxVariants = 10

var spaceRe = regexp.MustCompile(`\s+`)
var punctRe = regexp.MustCompile(`[·・:：\-—_]`)

func NormalizeVodTitle(name string) string {
	name = strings.TrimSpace(name)
	if name == "" {
		return ""
	}
	name = strings.ToLower(name)
	name = spaceRe.ReplaceAllString(name, "")
	name = punctRe.ReplaceAllString(name, "")
	return name
}

func BuildVodMergeKey(item model.VodItem) string {
	return NormalizeVodTitle(item.VodName)
}

func countPlayLines(item model.VodItem) int {
	from := item.VodPlayFrom
	if from == "" {
		return 0
	}
	if strings.Contains(from, "$$$") {
		return len(filterNonEmpty(strings.Split(from, "$$$")))
	}
	if strings.Contains(from, ",") {
		return len(filterNonEmpty(strings.Split(from, ",")))
	}
	return 1
}

func filterNonEmpty(parts []string) []string {
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

func getSourceOrder(store *config.SourceStore) map[int]int {
	order := make(map[int]int)
	for i, src := range store.Enabled() {
		order[src.ID] = i
	}
	return order
}

func pickPrimaryItem(items []model.MergeableVodItem, sourceOrder map[int]int) model.MergeableVodItem {
	best := items[0]
	for _, item := range items[1:] {
		aPic := boolToInt(best.VodPic != "")
		bPic := boolToInt(item.VodPic != "")
		if bPic != aPic {
			if bPic > aPic {
				best = item
			}
			continue
		}
		aLines := countPlayLines(best.VodItem)
		bLines := countPlayLines(item.VodItem)
		if bLines != aLines {
			if bLines > aLines {
				best = item
			}
			continue
		}
		aOrder, aOk := sourceOrder[best.SourceID]
		if !aOk {
			aOrder = 999
		}
		bOrder, bOk := sourceOrder[item.SourceID]
		if !bOk {
			bOrder = 999
		}
		if bOrder < aOrder {
			best = item
		}
	}
	return best
}

func boolToInt(v bool) int {
	if v {
		return 1
	}
	return 0
}

func pickBestVodMetadata(items []model.VodItem) model.VodItem {
	best := items[0]
	for _, item := range items[1:] {
		aPic := boolToInt(best.VodPic != "")
		bPic := boolToInt(item.VodPic != "")
		if bPic != aPic {
			if bPic > aPic {
				best = item
			}
			continue
		}
		aContent := len(best.VodContent)
		if aContent == 0 {
			aContent = len(best.VodBlurb)
		}
		bContent := len(item.VodContent)
		if bContent == 0 {
			bContent = len(item.VodBlurb)
		}
		if bContent > aContent {
			best = item
		}
	}
	return best
}

func buildVariants(items []model.MergeableVodItem) []model.VodVariant {
	variants := make([]model.VodVariant, 0)
	seen := make(map[string]bool)

	for _, item := range items {
		if item.SourceID == 0 {
			continue
		}
		vodID := item.VodID
		key := matchKey(item.SourceID, vodID)
		if seen[key] {
			continue
		}
		seen[key] = true
		variants = append(variants, model.VodVariant{
			SourceID:   item.SourceID,
			SourceName: item.SourceName,
			VodID:      vodID,
		})
	}
	return variants
}

func matchKey(sourceID int, vodID string) string {
	return strconv.Itoa(sourceID) + ":" + vodID
}

func MergeVodItems(items []model.MergeableVodItem, store *config.SourceStore) []model.MergedVodItem {
	sourceOrder := getSourceOrder(store)
	groups := make(map[string][]model.MergeableVodItem)

	for _, item := range items {
		key := BuildVodMergeKey(item.VodItem)
		groups[key] = append(groups[key], item)
	}

	merged := make([]model.MergedVodItem, 0, len(groups))
	for _, group := range groups {
		primary := pickPrimaryItem(group, sourceOrder)
		variants := buildVariants(group)
		primarySourceID := primary.SourceID
		if primarySourceID == 0 && len(variants) > 0 {
			primarySourceID = variants[0].SourceID
		}
		merged = append(merged, model.MergedVodItem{
			VodItem:         primary.VodItem,
			Variants:        variants,
			PrimarySourceID: primarySourceID,
		})
	}
	return merged
}

type MergedVodDetailResult struct {
	Vod             model.VodItem      `json:"vod"`
	PlaySources     []model.PlaySource `json:"playSources"`
	PrimarySourceID int                `json:"primarySourceId"`
	Variants        []model.VodVariant `json:"variants"`
}

func FetchMergedVodDetail(store *config.SourceStore, source model.Source, vodID string) (*MergedVodDetailResult, error) {
	primaryData, err := maccms.FetchVodDetail(source, vodID)
	if err != nil {
		return nil, err
	}
	if len(primaryData.List) == 0 {
		return nil, nil
	}
	primary := primaryData.List[0]
	mergeKey := BuildVodMergeKey(primary)

	type match struct {
		source model.Source
		vodID  string
	}
	matches := make([]match, 0)
	seen := make(map[string]bool)

	addMatch := func(s model.Source, id string) {
		key := matchKey(s.ID, id)
		if seen[key] {
			return
		}
		seen[key] = true
		matches = append(matches, match{source: s, vodID: id})
	}

	addMatch(source, vodID)

	for _, searchSource := range store.Enabled() {
		if len(matches) >= maxVariants {
			break
		}
		data, err := maccms.SearchVod(searchSource, primary.VodName, 1)
		if err != nil {
			continue
		}
		for _, item := range data.List {
			if BuildVodMergeKey(item) != mergeKey {
				continue
			}
			addMatch(searchSource, item.VodID)
			if len(matches) >= maxVariants {
				break
			}
		}
	}

	type vodEntry struct {
		source model.Source
		vod    model.VodItem
	}
	vodsWithSource := make([]parser.VodWithSource, 0, len(matches))

	for _, m := range matches {
		if m.source.ID == source.ID && m.vodID == vodID {
			vodsWithSource = append(vodsWithSource, parser.VodWithSource{Source: m.source, Vod: primary})
			continue
		}
		data, err := maccms.FetchVodDetail(m.source, m.vodID)
		if err != nil || len(data.List) == 0 {
			continue
		}
		vodsWithSource = append(vodsWithSource, parser.VodWithSource{Source: m.source, Vod: data.List[0]})
	}

	playSources := parser.MergePlaySourcesFromVods(vodsWithSource)
	vodItems := make([]model.VodItem, len(vodsWithSource))
	for i, e := range vodsWithSource {
		vodItems[i] = e.Vod
	}
	bestVod := pickBestVodMetadata(vodItems)

	variants := make([]model.VodVariant, len(vodsWithSource))
	for i, e := range vodsWithSource {
		variants[i] = model.VodVariant{
			SourceID:   e.Source.ID,
			SourceName: e.Source.Name,
			VodID:      e.Vod.VodID,
		}
	}

	return &MergedVodDetailResult{
		Vod: model.VodItem{
			VodID:       primary.VodID,
			VodName:     primary.VodName,
			VodPic:      bestVod.VodPic,
			VodRemarks:  bestVod.VodRemarks,
			VodYear:     bestVod.VodYear,
			VodArea:     bestVod.VodArea,
			VodClass:    bestVod.VodClass,
			VodBlurb:    bestVod.VodBlurb,
			VodContent:  bestVod.VodContent,
			VodPlayFrom: bestVod.VodPlayFrom,
			VodPlayURL:  bestVod.VodPlayURL,
			TypeID:      bestVod.TypeID,
			TypeName:    bestVod.TypeName,
		},
		PlaySources:     playSources,
		PrimarySourceID: source.ID,
		Variants:        variants,
	}, nil
}
