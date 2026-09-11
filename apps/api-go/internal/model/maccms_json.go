package model

import (
	"encoding/json"
	"fmt"
)

// FlexString unmarshals JSON number or string into a Go string.
type FlexString string

func (f *FlexString) UnmarshalJSON(data []byte) error {
	var s string
	if err := json.Unmarshal(data, &s); err == nil {
		*f = FlexString(s)
		return nil
	}
	var n json.Number
	if err := json.Unmarshal(data, &n); err == nil {
		*f = FlexString(n.String())
		return nil
	}
	return fmt.Errorf("FlexString: cannot unmarshal %s", string(data))
}

func (f FlexString) String() string {
	return string(f)
}

// FlexInt unmarshals JSON number or string into int.
type FlexInt int

func (f *FlexInt) UnmarshalJSON(data []byte) error {
	var n int
	if err := json.Unmarshal(data, &n); err == nil {
		*f = FlexInt(n)
		return nil
	}
	var s string
	if err := json.Unmarshal(data, &s); err == nil {
		var parsed int
		_, scanErr := fmt.Sscanf(s, "%d", &parsed)
		if scanErr != nil {
			return scanErr
		}
		*f = FlexInt(parsed)
		return nil
	}
	return fmt.Errorf("FlexInt: cannot unmarshal %s", string(data))
}

func (f FlexInt) Int() int {
	return int(f)
}

// MacCmsVodItem is the raw MacCMS vod item before normalization.
type MacCmsVodItem struct {
	VodID       FlexString `json:"vod_id"`
	VodName     string     `json:"vod_name"`
	VodPic      string     `json:"vod_pic"`
	VodRemarks  string     `json:"vod_remarks"`
	VodYear     string     `json:"vod_year"`
	VodArea     string     `json:"vod_area"`
	VodClass    string     `json:"vod_class"`
	VodBlurb    string     `json:"vod_blurb"`
	VodContent  string     `json:"vod_content"`
	VodPlayFrom string     `json:"vod_play_from"`
	VodPlayURL  string     `json:"vod_play_url"`
	VodTime     FlexString `json:"vod_time"`
	VodTimeAdd  FlexString `json:"vod_time_add"`
	TypeID      int        `json:"type_id"`
	TypeName    string     `json:"type_name"`
}

func (m MacCmsVodItem) ToVodItem() VodItem {
	vodTime := ParseVodTimeSec(m.VodTime.String())
	if add := ParseVodTimeSec(m.VodTimeAdd.String()); add > vodTime {
		vodTime = add
	}
	return VodItem{
		VodID:       m.VodID.String(),
		VodName:     m.VodName,
		VodPic:      m.VodPic,
		VodRemarks:  m.VodRemarks,
		VodYear:     m.VodYear,
		VodArea:     m.VodArea,
		VodClass:    m.VodClass,
		VodBlurb:    m.VodBlurb,
		VodContent:  m.VodContent,
		VodPlayFrom: m.VodPlayFrom,
		VodPlayURL:  m.VodPlayURL,
		VodTime:     vodTime,
		TypeID:      m.TypeID,
		TypeName:    m.TypeName,
	}
}

type macCmsListResponseRaw struct {
	Code      int             `json:"code"`
	Msg       string          `json:"msg"`
	Page      FlexInt         `json:"page"`
	PageCount FlexInt         `json:"pagecount"`
	Limit     string          `json:"limit"`
	Total     FlexInt         `json:"total"`
	List      []MacCmsVodItem `json:"list"`
	Class     []VodType       `json:"class"`
}

func ParseMacCmsListResponse(data []byte) (*MacCmsListResponse, error) {
	var raw macCmsListResponseRaw
	if err := json.Unmarshal(data, &raw); err != nil {
		return nil, err
	}
	list := make([]VodItem, len(raw.List))
	for i, item := range raw.List {
		list[i] = item.ToVodItem()
	}
	return &MacCmsListResponse{
		Code: raw.Code, Msg: raw.Msg, Page: raw.Page.Int(),
		PageCount: raw.PageCount.Int(), Limit: raw.Limit, Total: raw.Total.Int(),
		List: list, Class: raw.Class,
	}, nil
}

type macCmsDetailResponseRaw struct {
	Code int             `json:"code"`
	Msg  string          `json:"msg"`
	List []MacCmsVodItem `json:"list"`
}

func ParseMacCmsDetailResponse(data []byte) (*MacCmsDetailResponse, error) {
	var raw macCmsDetailResponseRaw
	if err := json.Unmarshal(data, &raw); err != nil {
		return nil, err
	}
	list := make([]VodItem, len(raw.List))
	for i, item := range raw.List {
		list[i] = item.ToVodItem()
	}
	return &MacCmsDetailResponse{Code: raw.Code, Msg: raw.Msg, List: list}, nil
}
