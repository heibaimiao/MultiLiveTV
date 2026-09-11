package bpz5

import (
	"context"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/heibaimiao/multilivetv/api-go/internal/model"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/merge"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/parser"
)

const (
	matchScoreThreshold = 80
	maxEnrichEpisodes   = 40
	enrichConcurrency   = 4
)

// EnrichOfficialPlaySources searches bpz5 by title and returns official ticket play sources.
// Failures return nil (caller keeps MacCMS-only sources).
func (c *Client) EnrichOfficialPlaySources(vod model.VodItem, existing []model.PlaySource) []model.PlaySource {
	if !c.Enabled() {
		return nil
	}
	title := strings.TrimSpace(vod.VodName)
	if title == "" {
		return nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	type result struct {
		sources []model.PlaySource
	}
	ch := make(chan result, 1)
	go func() {
		ch <- result{sources: c.enrichSync(title, vod.VodYear, existing)}
	}()

	select {
	case <-ctx.Done():
		return nil
	case r := <-ch:
		return r.sources
	}
}

func (c *Client) enrichSync(title, year string, existing []model.PlaySource) []model.PlaySource {
	cards, err := c.SearchCatalog(title, 8)
	if err != nil || len(cards) == 0 {
		return nil
	}
	best, score := PickBestCard(title, year, cards)
	if best == nil || score < matchScoreThreshold {
		return nil
	}
	variantID := best.VariantID()
	if variantID == "" {
		return nil
	}

	epLimit := episodeBudget(existing)
	episodes, err := c.FetchEpisodes(variantID, epLimit)
	if err != nil || len(episodes) == 0 {
		return nil
	}
	if len(episodes) > epLimit {
		episodes = episodes[:epLimit]
	}

	_ = c.EnsureAnonymousSession(false)

	type epLines struct {
		index int
		ep    Episode
		lines []LineOption
	}
	collected := make([]epLines, len(episodes))
	sem := make(chan struct{}, enrichConcurrency)
	var wg sync.WaitGroup
	for i, ep := range episodes {
		if strings.TrimSpace(ep.Token) == "" {
			continue
		}
		wg.Add(1)
		sem <- struct{}{}
		go func(i int, ep Episode) {
			defer wg.Done()
			defer func() { <-sem }()
			lines, err := c.PlaybackResolve(ep.Token)
			if err != nil {
				return
			}
			var official []LineOption
			for _, line := range lines {
				if IsOfficialParseLine(line) {
					official = append(official, line)
				}
			}
			collected[i] = epLines{index: i, ep: ep, lines: official}
		}(i, ep)
	}
	wg.Wait()

	byProvider := map[string]*model.PlaySource{}
	order := make([]string, 0)
	for _, item := range collected {
		if len(item.lines) == 0 {
			continue
		}
		epName := item.ep.Title
		if epName == "" {
			epName = existingEpisodeName(existing, item.index)
		}
		if epName == "" {
			epName = "第" + itoa(item.index+1) + "集"
		}
		for _, line := range item.lines {
			provider := strings.TrimSpace(line.ProviderID)
			playFrom := strings.TrimSpace(line.PlayFrom)
			if provider == "" {
				provider = playFrom
			}
			if provider == "" {
				continue
			}
			key := officialLineKey(provider, playFrom)
			ps, ok := byProvider[key]
			if !ok {
				label := line.ProviderName
				if label == "" {
					label = line.Label
				}
				if label == "" {
					label = parser.FormatPlaySourceName(playFrom, 0)
				}
				if label == "" || strings.HasPrefix(label, "线路") {
					label = provider
				}
				weight := line.PreferenceWeight
				if weight <= 0 {
					// 热播聚合共用 provider_id，按 play_from 区分权重
					if provider == "official-hot-playback" {
						weight = parser.WeightFor(playFrom, "", 0)
					} else {
						weight = parser.WeightFor(playFrom, provider, 0)
					}
				}
				ps = &model.PlaySource{
					Name:         label,
					Key:          key,
					Episodes:     make([]model.Episode, len(episodes)),
					Weight:       weight,
					Mode:         "ticket",
					PlayFrom:     playFrom,
					ProviderID:   provider,
					RequiresAuth: true,
				}
				byProvider[key] = ps
				order = append(order, key)
			}
			url := strings.TrimSpace(line.URL)
			if url != "" && !strings.HasPrefix(url, "resolve://") && strings.HasPrefix(url, "rpt1.") {
				url = "resolve://" + url
			}
			ps.Episodes[item.index] = model.Episode{Name: epName, URL: url}
		}
	}

	out := make([]model.PlaySource, 0, len(order))
	for _, key := range order {
		ps := byProvider[key]
		filled := 0
		for _, ep := range ps.Episodes {
			if ep.URL != "" {
				filled++
			}
		}
		if filled == 0 {
			continue
		}
		out = append(out, *ps)
	}
	parser.SortPlaySources(out)
	return out
}

func officialLineKey(providerID, playFrom string) string {
	providerID = strings.TrimSpace(providerID)
	playFrom = strings.TrimSpace(playFrom)
	if providerID == "" {
		return "bpz5:" + playFrom
	}
	if playFrom == "" || playFrom == providerID {
		return "bpz5:" + providerID
	}
	return "bpz5:" + providerID + ":" + playFrom
}

func episodeBudget(existing []model.PlaySource) int {
	maxEp := 1
	for _, ps := range existing {
		if len(ps.Episodes) > maxEp {
			maxEp = len(ps.Episodes)
		}
	}
	if maxEp > maxEnrichEpisodes {
		return maxEnrichEpisodes
	}
	return maxEp
}

func existingEpisodeName(existing []model.PlaySource, index int) string {
	for _, ps := range existing {
		if index < len(ps.Episodes) && ps.Episodes[index].Name != "" {
			return ps.Episodes[index].Name
		}
	}
	return ""
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b [16]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	return string(b[i:])
}

// PickBestCard scores catalog cards against query title/year.
func PickBestCard(queryTitle, queryYear string, cards []CatalogCard) (*CatalogCard, int) {
	qNorm := merge.NormalizeVodTitle(queryTitle)
	qYear := normalizeYear(queryYear)
	bestScore := -1
	var best *CatalogCard
	for i := range cards {
		card := &cards[i]
		if card.HasPlayback != nil && !*card.HasPlayback {
			continue
		}
		score := scoreTitle(qNorm, merge.NormalizeVodTitle(card.Title))
		if qYear != "" && normalizeYear(card.YearString()) == qYear {
			score += 15
		}
		if score > bestScore {
			bestScore = score
			best = card
		}
	}
	return best, bestScore
}

func scoreTitle(query, candidate string) int {
	if query == "" || candidate == "" {
		return 0
	}
	if query == candidate {
		return 100
	}
	if strings.Contains(candidate, query) || strings.Contains(query, candidate) {
		diff := utf8.RuneCountInString(candidate) - utf8.RuneCountInString(query)
		if diff < 0 {
			diff = -diff
		}
		score := 90 - diff*3
		if score < 50 {
			return 50
		}
		return score
	}
	return 0
}

func normalizeYear(year string) string {
	year = strings.TrimSpace(year)
	if year == "" {
		return ""
	}
	var digits strings.Builder
	for _, r := range year {
		if r >= '0' && r <= '9' {
			digits.WriteRune(r)
		}
		if digits.Len() == 4 {
			break
		}
	}
	return digits.String()
}
