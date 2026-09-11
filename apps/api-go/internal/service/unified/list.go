package unified

import (
	"sort"
	"strconv"
	"sync"

	"github.com/heibaimiao/multilivetv/api-go/internal/config"
	"github.com/heibaimiao/multilivetv/api-go/internal/model"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/maccms"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/merge"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/parser"
)

const maxFanout = 8

type ListResult struct {
	Cat           string
	Label         string
	Page          int
	PageCount     int
	Total         int
	List          []model.MergedVodItem
	SourcesUsed   []int
	SourcesFailed []int
	Code          int
	Msg           string
	Limit         string
}

func FetchListBySlug(store *config.SourceStore, slug string, page int) (*ListResult, error) {
	node, ok := Find(slug)
	if !ok {
		return nil, ErrNotFound
	}
	if page < 1 {
		page = 1
	}

	enabled := store.Enabled()
	enabledIDs := make([]int, 0, len(enabled))
	for _, src := range enabled {
		enabledIDs = append(enabledIDs, src.ID)
	}
	mappings := SourceTypeIDs(node, enabledIDs)
	sort.SliceStable(mappings, func(i, j int) bool {
		return parser.SourceWeight(mappings[i].SourceID) > parser.SourceWeight(mappings[j].SourceID)
	})
	if len(mappings) == 0 {
		return &ListResult{
			Cat: slug, Label: node.Label, Page: page, Code: 1, Msg: "no mapped sources",
			Limit: "0", List: []model.MergedVodItem{},
		}, nil
	}

	type jobResult struct {
		sourceID int
		list     []model.MergeableVodItem
		total    int
		pages    int
		err      error
	}

	jobs := make(chan SourceMapping)
	results := make(chan jobResult, len(mappings))
	var wg sync.WaitGroup
	workers := maxFanout
	if workers > len(mappings) {
		workers = len(mappings)
	}
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for mapping := range jobs {
				src := store.ByID(mapping.SourceID)
				if src == nil {
					results <- jobResult{sourceID: mapping.SourceID, err: ErrNotFound}
					continue
				}
				typeID := mapping.TypeID
				data, err := maccms.FetchVodList(*src, page, &typeID)
				if err != nil {
					results <- jobResult{sourceID: mapping.SourceID, err: err}
					continue
				}
				items := make([]model.MergeableVodItem, 0, len(data.List))
				for _, item := range data.List {
					items = append(items, model.MergeableVodItem{
						VodItem:    item,
						SourceID:   src.ID,
						SourceName: src.Name,
					})
				}
				results <- jobResult{
					sourceID: src.ID,
					list:     items,
					total:    data.Total,
					pages:    data.PageCount,
				}
			}
		}()
	}
	go func() {
		for _, mapping := range mappings {
			jobs <- mapping
		}
		close(jobs)
		wg.Wait()
		close(results)
	}()

	var all []model.MergeableVodItem
	used := make([]int, 0)
	failed := make([]int, 0)
	pagecount := 1
	total := 0
	for res := range results {
		if res.err != nil || len(res.list) == 0 {
			failed = append(failed, res.sourceID)
			continue
		}
		used = append(used, res.sourceID)
		all = append(all, res.list...)
		if res.pages > pagecount {
			pagecount = res.pages
		}
		total += res.total
	}

	merged := merge.SortMergedByUpdatedDesc(merge.MergeVodItems(all, store))
	return &ListResult{
		Cat:           slug,
		Label:         node.Label,
		Page:          page,
		PageCount:     pagecount,
		Total:         total,
		List:          merged,
		SourcesUsed:   used,
		SourcesFailed: failed,
		Code:          1,
		Msg:           "ok",
		Limit:         strconv.Itoa(len(merged)),
	}, nil
}

var ErrNotFound = errNotFound("category not found")

type errNotFound string

func (e errNotFound) Error() string { return string(e) }
