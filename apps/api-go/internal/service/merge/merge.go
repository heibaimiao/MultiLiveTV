package merge

import (
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/heibaimiao/multilivetv/api-go/internal/config"
	"github.com/heibaimiao/multilivetv/api-go/internal/model"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/maccms"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/parser"
)

const maxVariants = 16

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

var yearRe = regexp.MustCompile(`\d{4}`)

func currentCalendarYear() int {
	return time.Now().In(time.FixedZone("CST", 8*3600)).Year()
}

func maxPlausibleReleaseYear() int {
	return currentCalendarYear() + 1
}

func IsDisplayableReleaseYear(year int) bool {
	return year >= 1900 && year <= maxPlausibleReleaseYear()
}

func rawYearDigits(year string) string {
	year = strings.TrimSpace(year)
	if year == "" {
		return ""
	}
	return yearRe.FindString(year)
}

func yearFromVodTime(vodTime int64, fallback int) int {
	if vodTime <= 0 {
		return fallback
	}
	return time.Unix(vodTime, 0).In(time.FixedZone("CST", 8*3600)).Year()
}

// SortYearValue ranks titles. Future placeholders (e.g. 2030) use the current
// calendar year so recently-added films still surface with this year's content.
func SortYearValue(year string, vodTime int64) int {
	current := currentCalendarYear()
	digits := rawYearDigits(year)
	if digits != "" {
		if n, err := strconv.Atoi(digits); err == nil {
			if n >= 1900 && n <= current+1 {
				return n
			}
			if n > current+1 {
				return current
			}
		}
	}
	return yearFromVodTime(vodTime, 0)
}

func NormalizeVodYear(year string) string {
	digits := rawYearDigits(year)
	if digits == "" {
		return ""
	}
	n, err := strconv.Atoi(digits)
	if err != nil || !IsDisplayableReleaseYear(n) {
		return ""
	}
	return digits
}

func YearValue(year string) int {
	y := NormalizeVodYear(year)
	if y == "" {
		return 0
	}
	n, err := strconv.Atoi(y)
	if err != nil {
		return 0
	}
	return n
}

func BuildVodMergeKey(item model.VodItem) string {
	return NormalizeVodTitle(item.VodName)
}

// IsCompatibleVodMatch is used for detail cross-source search: same title,
// and years match when both sides have a concrete year.
func IsCompatibleVodMatch(primary, candidate model.VodItem) bool {
	if NormalizeVodTitle(primary.VodName) != NormalizeVodTitle(candidate.VodName) {
		return false
	}
	py := NormalizeVodYear(primary.VodYear)
	cy := NormalizeVodYear(candidate.VodYear)
	if py == "" || cy == "" {
		return true
	}
	return py == cy
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
		aWeight := parser.SourceWeight(best.SourceID)
		bWeight := parser.SourceWeight(item.SourceID)
		if bWeight != aWeight {
			if bWeight > aWeight {
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
	sort.SliceStable(variants, func(i, j int) bool {
		return parser.SourceWeight(variants[i].SourceID) > parser.SourceWeight(variants[j].SourceID)
	})
	return variants
}

func matchKey(sourceID int, vodID string) string {
	return strconv.Itoa(sourceID) + ":" + vodID
}

func MergeVodItems(items []model.MergeableVodItem, store *config.SourceStore) []model.MergedVodItem {
	sourceOrder := getSourceOrder(store)
	groups, order := groupMergeableItems(items)

	merged := make([]model.MergedVodItem, 0, len(order))
	for _, key := range order {
		group := groups[key]
		primary := pickPrimaryItem(group, sourceOrder)
		variants := buildVariants(group)
		primarySourceID := primary.SourceID
		if primarySourceID == 0 && len(variants) > 0 {
			primarySourceID = variants[0].SourceID
		}
		vod := primary.VodItem
		if latest := latestVodTime(group); latest > vod.VodTime {
			vod.VodTime = latest
		}
		if y := bestYear(group); y != "" && NormalizeVodYear(vod.VodYear) == "" {
			vod.VodYear = y
		}
		merged = append(merged, model.MergedVodItem{
			VodItem:         vod,
			Variants:        variants,
			PrimarySourceID: primarySourceID,
		})
	}
	return merged
}

func bestYear(items []model.MergeableVodItem) string {
	best := ""
	bestN := 0
	for _, item := range items {
		y := NormalizeVodYear(item.VodYear)
		if y == "" {
			continue
		}
		n := YearValue(y)
		if n >= bestN {
			bestN = n
			best = y
		}
	}
	return best
}

// groupMergeableItems groups by title; keeps distinct concrete years apart;
// folds empty-year rows into the only / newest year bucket.
func groupMergeableItems(items []model.MergeableVodItem) (map[string][]model.MergeableVodItem, []string) {
	byTitle := make(map[string][]model.MergeableVodItem)
	titleOrder := make([]string, 0)
	for _, item := range items {
		title := NormalizeVodTitle(item.VodName)
		if title == "" {
			continue
		}
		if _, ok := byTitle[title]; !ok {
			titleOrder = append(titleOrder, title)
		}
		byTitle[title] = append(byTitle[title], item)
	}

	groups := make(map[string][]model.MergeableVodItem)
	order := make([]string, 0)
	for _, title := range titleOrder {
		group := byTitle[title]
		concreteYears := orderedUniqueYears(group)
		if len(concreteYears) <= 1 {
			key := title
			if len(concreteYears) == 1 {
				key = title + "|" + concreteYears[0]
			}
			order = append(order, key)
			groups[key] = group
			continue
		}

		byYear := make(map[string][]model.MergeableVodItem)
		yearOrder := make([]string, 0)
		emptyYear := make([]model.MergeableVodItem, 0)
		for _, entry := range group {
			year := NormalizeVodYear(entry.VodYear)
			if year == "" {
				emptyYear = append(emptyYear, entry)
				continue
			}
			if _, ok := byYear[year]; !ok {
				yearOrder = append(yearOrder, year)
			}
			byYear[year] = append(byYear[year], entry)
		}

		if len(emptyYear) > 0 {
			target := yearOrder[0]
			bestTime := latestVodTime(byYear[target])
			for _, year := range yearOrder[1:] {
				if t := latestVodTime(byYear[year]); t > bestTime {
					bestTime = t
					target = year
				}
			}
			byYear[target] = append(byYear[target], emptyYear...)
		}

		for _, year := range yearOrder {
			key := title + "|" + year
			order = append(order, key)
			groups[key] = byYear[year]
		}
	}
	return groups, order
}

func orderedUniqueYears(group []model.MergeableVodItem) []string {
	seen := make(map[string]struct{})
	years := make([]string, 0)
	for _, entry := range group {
		year := NormalizeVodYear(entry.VodYear)
		if year == "" {
			continue
		}
		if _, ok := seen[year]; ok {
			continue
		}
		seen[year] = struct{}{}
		years = append(years, year)
	}
	return years
}

func latestVodTime(items []model.MergeableVodItem) int64 {
	var best int64
	for _, item := range items {
		if t := model.VodUpdatedAtSec(item.VodItem); t > best {
			best = t
		}
	}
	return best
}

// SortMergedByUpdatedDesc sorts by release year first, then update time.
// Future placeholder years rank using the update-time year.
func SortMergedByUpdatedDesc(items []model.MergedVodItem) []model.MergedVodItem {
	out := make([]model.MergedVodItem, len(items))
	copy(out, items)
	sort.SliceStable(out, func(i, j int) bool {
		iy := SortYearValue(out[i].VodYear, model.VodUpdatedAtSec(out[i].VodItem))
		jy := SortYearValue(out[j].VodYear, model.VodUpdatedAtSec(out[j].VodItem))
		if iy != jy {
			return iy > jy
		}
		return model.VodUpdatedAtSec(out[i].VodItem) > model.VodUpdatedAtSec(out[j].VodItem)
	})
	return out
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
			if !IsCompatibleVodMatch(primary, item) {
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
		if !IsCompatibleVodMatch(primary, data.List[0]) {
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
