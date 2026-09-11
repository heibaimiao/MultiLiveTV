package handler

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/heibaimiao/multilivetv/api-go/internal/config"
	"github.com/heibaimiao/multilivetv/api-go/internal/model"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/bpz5"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/category"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/maccms"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/merge"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/parser"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/unified"
)

type Handler struct {
	Sources  *config.SourceStore
	Category *category.Cache
	BPZ5     *bpz5.Client
}

func New(sources *config.SourceStore) *Handler {
	return &Handler{Sources: sources, Category: category.NewCache()}
}

func NewWithBPZ5(sources *config.SourceStore, client *bpz5.Client) *Handler {
	h := New(sources)
	h.BPZ5 = client
	return h
}

func (h *Handler) GetSources(c *gin.Context) {
	enabled := h.Sources.Enabled()
	out := make([]gin.H, 0, len(enabled))
	for _, src := range enabled {
		out = append(out, gin.H{
			"id":       src.ID,
			"name":     src.Name,
			"url":      src.URL,
			"flag":     src.Flag,
			"vip_only": src.VipOnly,
		})
	}
	c.JSON(http.StatusOK, gin.H{"sources": out})
}

func (h *Handler) GetVodList(c *gin.Context) {
	sourceIDParam := c.Query("sourceId")
	page, _ := strconv.Atoi(c.DefaultQuery("pg", "1"))
	if page < 1 {
		page = 1
	}
	typeID := config.ParseTypeID(c.Query("t"))
	cat := strings.TrimSpace(c.Query("cat"))

	if cat != "" {
		data, err := unified.FetchListBySlug(h.Sources, cat, page)
		if err == unified.ErrNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "Category not found"})
			return
		}
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{
			"cat":            data.Cat,
			"label":          data.Label,
			"sourcesUsed":    data.SourcesUsed,
			"sourcesFailed":  data.SourcesFailed,
			"code":           data.Code,
			"msg":            data.Msg,
			"page":           data.Page,
			"pagecount":      data.PageCount,
			"limit":          data.Limit,
			"total":          data.Total,
			"list":           data.List,
		})
		return
	}

	if sourceIDParam != "" {
		id, err := strconv.Atoi(sourceIDParam)
		if err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Source not found"})
			return
		}
		src := h.Sources.ByID(id)
		if src == nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Source not found"})
			return
		}
		data, err := category.FetchVodListByTypeMerged(h.Sources, *src, typeID, page)
		if err != nil {
			c.JSON(http.StatusOK, emptyListResponse(src, typeID, page, err.Error()))
			return
		}
		if len(data.List) > 0 {
			c.JSON(http.StatusOK, listResponse(src, typeID, data))
			return
		}
		c.JSON(http.StatusOK, emptyListResponse(src, typeID, page, "ok"))
		return
	}

	var lastError string
	for _, src := range h.Sources.Enabled() {
		data, err := category.FetchVodListByTypeMerged(h.Sources, src, typeID, page)
		if err != nil {
			lastError = err.Error()
			continue
		}
		if len(data.List) > 0 {
			c.JSON(http.StatusOK, listResponse(&src, typeID, data))
			return
		}
	}

	fallback := h.Sources.Default()
	if fallback == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "No sources available"})
		return
	}
	msg := lastError
	if msg == "" {
		msg = "ok"
	}
	c.JSON(http.StatusOK, emptyListResponse(fallback, typeID, page, msg))
}

func (h *Handler) GetUnifiedCategories(c *gin.Context) {
	c.JSON(http.StatusOK, unified.Public())
}

func listResponse(src *model.Source, typeID *int, data *category.ListResult) gin.H {
	return gin.H{
		"source":    gin.H{"id": src.ID, "name": src.Name},
		"typeId":    typeID,
		"code":      data.Code,
		"msg":       data.Msg,
		"page":      data.Page,
		"pagecount": data.PageCount,
		"limit":     data.Limit,
		"total":     data.Total,
		"list":      data.List,
	}
}

func emptyListResponse(src *model.Source, typeID *int, page int, msg string) gin.H {
	return gin.H{
		"source":    gin.H{"id": src.ID, "name": src.Name},
		"typeId":    typeID,
		"code":      1,
		"msg":       msg,
		"page":      page,
		"pagecount": 0,
		"limit":     "24",
		"total":     0,
		"list":      []any{},
	}
}

func (h *Handler) GetVodDetail(c *gin.Context) {
	sourceID := c.Query("sourceId")
	ids := c.Query("ids")
	if sourceID == "" || ids == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "sourceId and ids are required"})
		return
	}
	id, err := strconv.Atoi(sourceID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Source not found"})
		return
	}
	src := h.Sources.ByID(id)
	if src == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Source not found"})
		return
	}

	merged, err := merge.FetchMergedVodDetail(h.Sources, *src, ids)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
		return
	}
	if merged == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Vod not found"})
		return
	}

	playSources := merged.PlaySources
	if h.BPZ5 != nil && h.BPZ5.Enabled() {
		if official := h.BPZ5.EnrichOfficialPlaySources(merged.Vod, merged.PlaySources); len(official) > 0 {
			playSources = append(append([]model.PlaySource{}, official...), merged.PlaySources...)
			parser.SortPlaySources(playSources)
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"source":      gin.H{"id": src.ID, "name": src.Name},
		"vod":         merged.Vod,
		"playSources": playSources,
		"variants":    merged.Variants,
		"merged":      true,
	})
}

func (h *Handler) SearchVod(c *gin.Context) {
	keyword := c.Query("wd")
	if keyword == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "wd is required"})
		return
	}
	page, _ := strconv.Atoi(c.DefaultQuery("pg", "1"))
	if page < 1 {
		page = 1
	}

	var enabled []model.Source
	if sourceID := c.Query("sourceId"); sourceID != "" {
		id, err := strconv.Atoi(sourceID)
		if err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "No sources available"})
			return
		}
		src := h.Sources.ByID(id)
		if src == nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "No sources available"})
			return
		}
		enabled = []model.Source{*src}
	} else {
		enabled = h.Sources.Enabled()
	}

	mergeable := make([]model.MergeableVodItem, 0)
	for _, src := range enabled {
		data, err := maccms.SearchVod(src, keyword, page)
		if err != nil {
			continue
		}
		for _, item := range data.List {
			mergeable = append(mergeable, model.MergeableVodItem{
				VodItem:    item,
				SourceID:   src.ID,
				SourceName: src.Name,
			})
		}
	}

	list := merge.SortMergedByUpdatedDesc(merge.MergeVodItems(mergeable, h.Sources))
	c.JSON(http.StatusOK, gin.H{
		"keyword": keyword,
		"merged":  true,
		"total":   len(list),
		"list":    list,
	})
}

func (h *Handler) GetVodTypes(c *gin.Context) {
	var source *model.Source
	if sourceID := c.Query("sourceId"); sourceID != "" {
		id, err := strconv.Atoi(sourceID)
		if err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Source not found"})
			return
		}
		source = h.Sources.ByID(id)
	} else {
		source = h.Sources.Default()
	}
	if source == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Source not found"})
		return
	}

	categories, err := h.Category.Get(h.Sources, source.ID)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"source":     gin.H{"id": source.ID, "name": source.Name},
		"categories": categories.All,
	})
}

func (h *Handler) GetVodPic(c *gin.Context) {
	sourceID := c.Query("sourceId")
	ids := c.Query("ids")
	if sourceID == "" || ids == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "sourceId and ids are required"})
		return
	}
	id, err := strconv.Atoi(sourceID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Source not found"})
		return
	}
	src := h.Sources.ByID(id)
	if src == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Source not found"})
		return
	}

	data, err := maccms.FetchVodDetail(*src, ids)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": err.Error(), "url": nil})
		return
	}
	var picURL any = nil
	if len(data.List) > 0 && data.List[0].VodPic != "" {
		picURL = data.List[0].VodPic
	}
	c.JSON(http.StatusOK, gin.H{"url": picURL})
}

func (h *Handler) ParsePlay(c *gin.Context) {
	sourceID := c.Query("sourceId")
	playURL := c.Query("url")
	if sourceID == "" || playURL == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "sourceId and url are required"})
		return
	}
	id, err := strconv.Atoi(sourceID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Source not found"})
		return
	}
	src := h.Sources.ByID(id)
	if src == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Source not found"})
		return
	}

	result := parser.ParsePlayAddress(*src, playURL)
	c.JSON(http.StatusOK, result)
}

func (h *Handler) ResolvePlay(c *gin.Context) {
	var req model.PlayResolveRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid json body"})
		return
	}

	mode := strings.TrimSpace(req.Mode)
	if mode == "" {
		mode = "direct"
	}
	echoPlayFrom := strings.TrimSpace(req.PlayFrom)

	switch mode {
	case "direct":
		if req.URL == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "url is required for direct mode"})
			return
		}
		jx := true
		if req.Jx != nil {
			jx = *req.Jx
		}
		if !jx || req.SourceID == 0 {
			c.JSON(http.StatusOK, model.ParseResult{URL: req.URL, Parsed: false, Mode: "direct", PlayFrom: echoPlayFrom})
			return
		}
		src := h.Sources.ByID(req.SourceID)
		if src == nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Source not found"})
			return
		}
		result := parser.ParsePlayAddress(*src, req.URL)
		result.PlayFrom = echoPlayFrom
		if result.Mode == "" {
			result.Mode = "direct"
		}
		c.JSON(http.StatusOK, result)
	case "ticket":
		ticket := bpz5.NormalizeTicket(req.Ticket, req.URL)
		if ticket == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "ticket is required for ticket mode"})
			return
		}
		if h.BPZ5 == nil || !h.BPZ5.Enabled() {
			c.JSON(http.StatusNotImplemented, gin.H{"error": "ticket_not_enabled"})
			return
		}
		resolved, err := h.BPZ5.ResolveLine(ticket)
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, model.ParseResult{
			URL:      resolved.URL,
			Parsed:   true,
			Mode:     "ticket",
			PlayFrom: echoPlayFrom,
		})
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "unsupported_mode"})
	}
}
