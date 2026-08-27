package model

import (
	"encoding/json"
	"testing"
)

func TestParseMacCmsListResponse_StringPage(t *testing.T) {
	raw := `{"code":1,"msg":"数据列表","page":"1","pagecount":1,"limit":"100","total":1,"list":[{"vod_id":93013,"vod_name":"鲨笼绝境","type_id":5,"type_name":"动作片"}]}`
	resp, err := ParseMacCmsListResponse([]byte(raw))
	if err != nil {
		t.Fatalf("parse error: %v", err)
	}
	if resp.Total != 1 {
		t.Fatalf("total = %d, want 1", resp.Total)
	}
	if len(resp.List) != 1 {
		t.Fatalf("list len = %d, want 1", len(resp.List))
	}
	if resp.List[0].VodName != "鲨笼绝境" {
		t.Fatalf("vod_name = %q", resp.List[0].VodName)
	}
	if resp.List[0].VodID != "93013" {
		t.Fatalf("vod_id = %q, want 93013", resp.List[0].VodID)
	}
}

func TestFlexString_Number(t *testing.T) {
	var item MacCmsVodItem
	if err := json.Unmarshal([]byte(`{"vod_id":93013,"vod_name":"test"}`), &item); err != nil {
		t.Fatal(err)
	}
	if item.VodID.String() != "93013" {
		t.Fatalf("got %q", item.VodID)
	}
}
