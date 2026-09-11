package model

import (
	"strconv"
	"strings"
	"time"
)

// ParseVodTimeSec converts MacCMS vod_time / vod_time_add to unix seconds.
func ParseVodTimeSec(raw string) int64 {
	s := strings.TrimSpace(raw)
	if s == "" {
		return 0
	}
	if n, err := strconv.ParseInt(s, 10, 64); err == nil {
		if n <= 0 {
			return 0
		}
		if n > 10_000_000_000 {
			return n / 1000
		}
		return n
	}

	parts := make([]int, 0, 6)
	cur := 0
	has := false
	flush := func() {
		if has {
			parts = append(parts, cur)
			cur = 0
			has = false
		}
	}
	for _, r := range s {
		if r >= '0' && r <= '9' {
			cur = cur*10 + int(r-'0')
			has = true
			continue
		}
		flush()
	}
	flush()
	if len(parts) < 3 {
		return 0
	}
	year, month, day := parts[0], parts[1], parts[2]
	hour, minute, second := 0, 0, 0
	if len(parts) > 3 {
		hour = parts[3]
	}
	if len(parts) > 4 {
		minute = parts[4]
	}
	if len(parts) > 5 {
		second = parts[5]
	}
	loc, err := time.LoadLocation("Asia/Shanghai")
	if err != nil {
		loc = time.FixedZone("CST", 8*3600)
	}
	t := time.Date(year, time.Month(month), day, hour, minute, second, 0, loc)
	if t.IsZero() {
		return 0
	}
	return t.Unix()
}

// VodUpdatedAtSec prefers vod_time, then falls back when only add-time exists.
// VodItem stores a single normalized VodTime already.
func VodUpdatedAtSec(item VodItem) int64 {
	if item.VodTime > 0 {
		return item.VodTime
	}
	return 0
}
