package parser

import (
	"fmt"
	"regexp"
	"strings"
)

var playSourceNames = map[string]string{
	"wjm3u8": "无尽", "snm3u8": "索尼", "ikm3u8": "爱酷", "ffm3u8": "非凡",
	"feifan": "非凡", "gsm3u8": "光速", "gsyun": "光速", "mtm3u8": "茅台",
	"mtyun": "茅台", "mym3u8": "猫眼", "hym3u8": "虎牙", "hyyun": "虎牙",
	"modum3u8": "魔都", "liangzi": "量子", "jsyun": "极速", "subyun": "速播",
	"lzm3u8": "量子", "jpm3u8": "极品", "jsm3u8": "极速", "subm3u8": "速播",
	"bfzym3u8": "暴风", "hnm3u8": "红牛", "hnyun": "红牛", "bjm3u8": "八戒",
	"wolong": "卧龙", "maotai": "茅台", "maoyan": "猫眼", "kcm3u8": "快车",
	"xlm3u8": "新浪", "dbm3u8": "豆瓣", "hkm3u8": "华为", "yym3u8": "丫丫",
	"ckm3u8": "CK", "dym3u8": "电影", "ukm3u8": "UK", "lsm3u8": "乐视",
	"qhm3u8": "奇虎", "ysm3u8": "影视", "huyam3u8": "虎牙", "tpm3u8": "淘片",
	"tkm3u8": "天空", "1080zyk": "1080看", "zuidam3u8": "最大", "kuaikan": "快看",
}

var playSourcePrefixNames = map[string]string{
	"wj": "无尽", "sn": "索尼", "ik": "爱酷", "lz": "量子", "ff": "非凡",
	"gs": "光速", "mt": "茅台", "my": "猫眼", "hy": "虎牙", "modu": "魔都",
	"jp": "极品", "js": "极速", "sub": "速播", "bfzy": "暴风", "hn": "红牛",
	"bj": "八戒", "kc": "快车", "xl": "新浪", "db": "豆瓣", "hk": "华为",
	"yy": "丫丫", "ck": "CK", "dy": "电影", "uk": "UK", "ls": "乐视",
	"qh": "奇虎", "ys": "影视", "tp": "淘片", "tk": "天空", "wolong": "卧龙",
	"feifan": "非凡", "maotai": "茅台", "maoyan": "猫眼", "gsyun": "光速",
	"mtyun": "茅台", "hyyun": "虎牙", "liangzi": "量子", "jsyun": "极速", "subyun": "速播",
}

var lineNamePattern = regexp.MustCompile(`(?i)^线路\d+$`)

func FormatPlaySourceName(raw string, index int) string {
	key := strings.ToLower(strings.TrimSpace(raw))
	if key == "" {
		return fmtLine(index)
	}
	if name, ok := playSourceNames[key]; ok {
		return name
	}
	prefix := strings.TrimSuffix(strings.TrimSuffix(key, "m3u8"), "yun")
	if name, ok := playSourcePrefixNames[prefix]; ok {
		return name
	}
	if lineNamePattern.MatchString(strings.TrimSpace(raw)) {
		return strings.TrimSpace(raw)
	}
	return fmtLine(index)
}

func fmtLine(index int) string {
	return fmt.Sprintf("线路%d", index+1)
}
