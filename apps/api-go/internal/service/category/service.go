package category

import (
	"strconv"
	"sync"
	"time"

	"github.com/heibaimiao/multilivetv/api-go/internal/config"
	"github.com/heibaimiao/multilivetv/api-go/internal/model"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/maccms"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/merge"
)

const cacheTTL = 5 * time.Minute

type Cache struct {
	mu    sync.RWMutex
	items map[int]cacheEntry
}

type cacheEntry struct {
	tree      model.CategoryTree
	expiresAt time.Time
}

func NewCache() *Cache {
	return &Cache{items: make(map[int]cacheEntry)}
}

func (c *Cache) Clear() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.items = make(map[int]cacheEntry)
}

func (c *Cache) Count() int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return len(c.items)
}

func (c *Cache) Get(store *config.SourceStore, sourceID int) (model.CategoryTree, error) {
	c.mu.RLock()
	entry, ok := c.items[sourceID]
	c.mu.RUnlock()
	if ok && time.Now().Before(entry.expiresAt) {
		return entry.tree, nil
	}

	source := store.ByID(sourceID)
	if source == nil {
		return model.CategoryTree{}, nil
	}
	types, err := maccms.FetchVodTypes(*source)
	if err != nil {
		return model.CategoryTree{}, err
	}
	tree := BuildCategoryTree(types)

	c.mu.Lock()
	c.items[sourceID] = cacheEntry{tree: tree, expiresAt: time.Now().Add(cacheTTL)}
	c.mu.Unlock()
	return tree, nil
}

func LoadCategories(store *config.SourceStore, source model.Source) ([]model.CategoryDef, error) {
	types, err := maccms.FetchVodTypes(source)
	if err != nil {
		return nil, err
	}
	return BuildCategoryTree(types).All, nil
}

func mergeListItems(store *config.SourceStore, source model.Source, items []model.VodItem) []model.MergedVodItem {
	mergeable := make([]model.MergeableVodItem, len(items))
	for i, item := range items {
		mergeable[i] = model.MergeableVodItem{
			VodItem:    item,
			SourceID:   source.ID,
			SourceName: source.Name,
		}
	}
	return merge.MergeVodItems(mergeable, store)
}

func FetchVodListByType(store *config.SourceStore, source model.Source, typeID *int, page int, knownTypes []model.VodType) (*model.MacCmsListResponse, error) {
	if typeID == nil {
		data, err := maccms.FetchVodList(source, page, nil)
		if err != nil {
			return nil, err
		}
		list := mergeListItems(store, source, data.List)
		data.List = mergedToVodItems(list)
		return data, nil
	}

	direct, err := maccms.FetchVodList(source, page, typeID)
	if err != nil {
		return nil, err
	}
	if len(direct.List) > 0 || direct.Total > 0 {
		list := mergeListItems(store, source, direct.List)
		direct.List = mergedToVodItems(list)
		return direct, nil
	}

	types := knownTypes
	if len(types) == 0 {
		types, err = maccms.FetchVodTypes(source)
		if err != nil {
			return direct, nil
		}
	}

	childIDs := GetChildTypeIds(types, *typeID)
	if len(childIDs) == 0 {
		return direct, nil
	}

	allItems := make([]model.VodItem, 0)
	pagecount := 1
	total := 0
	for _, childID := range childIDs {
		cid := childID
		data, err := maccms.FetchVodList(source, page, &cid)
		if err != nil {
			continue
		}
		allItems = append(allItems, data.List...)
		if data.PageCount > pagecount {
			pagecount = data.PageCount
		}
		total += data.Total
	}

	list := mergeListItems(store, source, allItems)
	return &model.MacCmsListResponse{
		Code:      1,
		Msg:       "ok",
		Page:      page,
		PageCount: pagecount,
		Limit:     string(rune(len(list))),
		Total:     total,
		List:      mergedToVodItems(list),
	}, nil
}

func mergedToVodItems(merged []model.MergedVodItem) []model.VodItem {
	// Return as VodItem slice but JSON will include variants via custom response
	items := make([]model.VodItem, len(merged))
	for i, m := range merged {
		items[i] = m.VodItem
	}
	return items
}

func FetchVodListByTypeMerged(store *config.SourceStore, source model.Source, typeID *int, page int) (*ListResult, error) {
	if typeID == nil {
		data, err := maccms.FetchVodList(source, page, nil)
		if err != nil {
			return nil, err
		}
		return &ListResult{
			Code: data.Code, Msg: data.Msg, Page: data.Page,
			PageCount: data.PageCount, Limit: data.Limit, Total: data.Total,
			List: mergeListItems(store, source, data.List),
		}, nil
	}

	direct, err := maccms.FetchVodList(source, page, typeID)
	if err != nil {
		return nil, err
	}
	if len(direct.List) > 0 || direct.Total > 0 {
		return &ListResult{
			Code: direct.Code, Msg: direct.Msg, Page: direct.Page,
			PageCount: direct.PageCount, Limit: direct.Limit, Total: direct.Total,
			List: mergeListItems(store, source, direct.List),
		}, nil
	}

	types, err := maccms.FetchVodTypes(source)
	if err != nil {
		return &ListResult{
			Code: direct.Code, Msg: direct.Msg, Page: direct.Page,
			PageCount: direct.PageCount, Limit: direct.Limit, Total: direct.Total,
			List: mergeListItems(store, source, direct.List),
		}, nil
	}

	childIDs := GetChildTypeIds(types, *typeID)
	if len(childIDs) == 0 {
		return &ListResult{
			Code: direct.Code, Msg: direct.Msg, Page: direct.Page,
			PageCount: direct.PageCount, Limit: direct.Limit, Total: direct.Total,
			List: mergeListItems(store, source, direct.List),
		}, nil
	}

	allItems := make([]model.VodItem, 0)
	pagecount := 1
	total := 0
	for _, childID := range childIDs {
		cid := childID
		data, err := maccms.FetchVodList(source, page, &cid)
		if err != nil {
			continue
		}
		allItems = append(allItems, data.List...)
		if data.PageCount > pagecount {
			pagecount = data.PageCount
		}
		total += data.Total
	}

	list := mergeListItems(store, source, allItems)
	return &ListResult{
		Code: 1, Msg: "ok", Page: page, PageCount: pagecount,
		Limit: fmtLimit(len(list)), Total: total, List: list,
	}, nil
}

type ListResult struct {
	Code      int                   `json:"code"`
	Msg       string                `json:"msg"`
	Page      int                   `json:"page"`
	PageCount int                   `json:"pagecount"`
	Limit     string                `json:"limit"`
	Total     int                   `json:"total"`
	List      []model.MergedVodItem `json:"list"`
}

func fmtLimit(n int) string {
	return strconv.Itoa(n)
}
