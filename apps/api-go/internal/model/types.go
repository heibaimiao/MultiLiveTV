package model

type Source struct {
	ID            int    `json:"id"`
	Name          string `json:"name"`
	URL           string `json:"url"`
	Flag          int    `json:"flag"`
	JxURL         string `json:"jx_url,omitempty"`
	JSONParse     string `json:"json_parse,omitempty"`
	DanmakuAPIURL string `json:"danmaku_api_url,omitempty"`
	VipOnly       bool   `json:"vip_only,omitempty"`
}

type VodType struct {
	TypeID   int    `json:"type_id"`
	TypeName string `json:"type_name"`
}

type VodItem struct {
	VodID       string `json:"vod_id"`
	VodName     string `json:"vod_name"`
	VodPic      string `json:"vod_pic"`
	VodRemarks  string `json:"vod_remarks,omitempty"`
	VodYear     string `json:"vod_year,omitempty"`
	VodArea     string `json:"vod_area,omitempty"`
	VodClass    string `json:"vod_class,omitempty"`
	VodBlurb    string `json:"vod_blurb,omitempty"`
	VodContent  string `json:"vod_content,omitempty"`
	VodPlayFrom string `json:"vod_play_from,omitempty"`
	VodPlayURL  string `json:"vod_play_url,omitempty"`
	TypeID      int    `json:"type_id,omitempty"`
	TypeName    string `json:"type_name,omitempty"`
}

type VodVariant struct {
	SourceID   int    `json:"sourceId"`
	SourceName string `json:"sourceName"`
	VodID      string `json:"vodId"`
}

type MergedVodItem struct {
	VodItem
	Variants        []VodVariant `json:"variants"`
	PrimarySourceID int          `json:"primarySourceId"`
}

type MergeableVodItem struct {
	VodItem
	SourceID   int    `json:"sourceId,omitempty"`
	SourceName string `json:"sourceName,omitempty"`
}

type Episode struct {
	Name string `json:"name"`
	URL  string `json:"url"`
}

type PlaySource struct {
	Name     string    `json:"name"`
	Key      string    `json:"key"`
	Episodes []Episode `json:"episodes"`
	SourceID int       `json:"sourceId,omitempty"`
}

type MacCmsListResponse struct {
	Code      int        `json:"code"`
	Msg       string     `json:"msg"`
	Page      int        `json:"page"`
	PageCount int        `json:"pagecount"`
	Limit     string     `json:"limit"`
	Total     int        `json:"total"`
	List      []VodItem  `json:"list"`
	Class     []VodType  `json:"class,omitempty"`
}

type MacCmsDetailResponse struct {
	Code int       `json:"code"`
	Msg  string    `json:"msg"`
	List []VodItem `json:"list"`
}

type ParseResult struct {
	URL    string `json:"url"`
	Parsed bool   `json:"parsed"`
}

type CategoryDef struct {
	TypeID int    `json:"typeId"`
	Label  string `json:"label"`
}

type CategoryTree struct {
	All              []CategoryDef           `json:"all"`
	Primary          []CategoryDef           `json:"primary"`
	ChildrenByParent map[int][]CategoryDef   `json:"childrenByParent"`
}
