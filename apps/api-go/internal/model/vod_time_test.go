package model

import "testing"

func TestParseVodTimeSec(t *testing.T) {
	if got := ParseVodTimeSec("1710000000"); got != 1710000000 {
		t.Fatalf("unix sec: got %d", got)
	}
	if got := ParseVodTimeSec("1710000000000"); got != 1710000000 {
		t.Fatalf("unix ms: got %d", got)
	}
	if got := ParseVodTimeSec("2026-09-03 14:00:00"); got <= 0 {
		t.Fatalf("datetime string: got %d", got)
	}
	if got := ParseVodTimeSec(""); got != 0 {
		t.Fatalf("empty: got %d", got)
	}
}

func TestMacCmsVodItemToVodItemTime(t *testing.T) {
	item := MacCmsVodItem{
		VodID:      FlexString("1"),
		VodName:    "测试",
		VodTime:    FlexString("2020-01-01 00:00:00"),
		VodTimeAdd: FlexString("2026-09-03 12:00:00"),
	}
	vod := item.ToVodItem()
	want := ParseVodTimeSec("2026-09-03 12:00:00")
	if vod.VodTime != want {
		t.Fatalf("expected latest add time %d, got %d", want, vod.VodTime)
	}
}
