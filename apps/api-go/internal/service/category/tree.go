package category

import (
	"regexp"
	"strings"

	"github.com/heibaimiao/multilivetv/api-go/internal/model"
)

var typeAliases = map[string]string{
	"日本剧": "日剧", "韩国剧": "韩剧", "泰国剧": "泰剧", "台湾剧": "台剧",
	"香港剧": "港剧", "大陆剧": "国产剧", "记录片": "纪录片", "日本动漫": "日韩动漫",
	"连续剧": "剧集", "电影片": "电影", "综艺片": "综艺", "动漫片": "动漫",
}

var parentNames = map[string]bool{
	"电影": true, "剧集": true, "综艺": true, "动漫": true,
}

var closeTagRe = regexp.MustCompile(`\[关\]`)
var xSuffixRe = regexp.MustCompile(`(?i)x$`)

func NormalizeTypeName(typeName string) string {
	if typeName == "" {
		return ""
	}
	cleaned := closeTagRe.ReplaceAllString(typeName, "")
	cleaned = xSuffixRe.ReplaceAllString(strings.TrimSpace(cleaned), "")
	cleaned = strings.TrimSpace(cleaned)
	if alias, ok := typeAliases[cleaned]; ok {
		return alias
	}
	return cleaned
}

func IsTypeVisible(typeName string) bool {
	if strings.Contains(typeName, "[关]") {
		return false
	}
	if xSuffixRe.MatchString(strings.TrimSpace(typeName)) {
		return false
	}
	return true
}

func FilterVisibleTypes(types []model.VodType) []model.VodType {
	out := make([]model.VodType, 0, len(types))
	for _, t := range types {
		if IsTypeVisible(t.TypeName) {
			out = append(out, t)
		}
	}
	return out
}

func toDef(t model.VodType) model.CategoryDef {
	return model.CategoryDef{TypeID: t.TypeID, Label: NormalizeTypeName(t.TypeName)}
}

func isParentType(typeName string) bool {
	return parentNames[NormalizeTypeName(typeName)]
}

var filmSuffixRe = regexp.MustCompile(`片$`)
var dramaSuffixRe = regexp.MustCompile(`剧$`)
var animeRe = regexp.MustCompile(`动漫|动画`)
var varietyRe = regexp.MustCompile(`综艺`)

func GetChildTypeIds(types []model.VodType, parentID int) []int {
	var parent *model.VodType
	for i := range types {
		if types[i].TypeID == parentID {
			parent = &types[i]
			break
		}
	}
	if parent == nil || !isParentType(parent.TypeName) {
		return nil
	}

	parentName := NormalizeTypeName(parent.TypeName)
	visible := FilterVisibleTypes(types)
	childCandidates := make([]model.VodType, 0)
	for _, t := range visible {
		if t.TypeID == parentID || isParentType(t.TypeName) {
			continue
		}
		childCandidates = append(childCandidates, t)
	}

	var matcher func(string) bool
	switch parentName {
	case "电影":
		matcher = func(name string) bool {
			return (filmSuffixRe.MatchString(name) || name == "纪录片") && !animeRe.MatchString(name)
		}
	case "剧集":
		matcher = func(name string) bool {
			return dramaSuffixRe.MatchString(name) && name != "短剧"
		}
	case "综艺":
		matcher = func(name string) bool {
			return varietyRe.MatchString(name)
		}
	case "动漫":
		matcher = func(name string) bool {
			return animeRe.MatchString(name)
		}
	default:
		return nil
	}

	ids := make([]int, 0)
	for _, t := range childCandidates {
		if matcher(NormalizeTypeName(t.TypeName)) {
			ids = append(ids, t.TypeID)
		}
	}
	return ids
}

func BuildCategoryTree(types []model.VodType) model.CategoryTree {
	visible := FilterVisibleTypes(types)
	all := make([]model.CategoryDef, len(visible))
	for i, t := range visible {
		all[i] = toDef(t)
	}

	parents := make([]model.VodType, 0)
	parentIDs := make(map[int]bool)
	for _, t := range visible {
		if isParentType(t.TypeName) {
			parents = append(parents, t)
			parentIDs[t.TypeID] = true
		}
	}

	childrenByParent := make(map[int][]model.CategoryDef)
	for _, parent := range parents {
		childIDs := GetChildTypeIds(visible, parent.TypeID)
		children := make([]model.CategoryDef, 0, len(childIDs))
		for _, id := range childIDs {
			for _, t := range visible {
				if t.TypeID == id {
					children = append(children, toDef(t))
					break
				}
			}
		}
		childrenByParent[parent.TypeID] = children
	}

	childIDSet := make(map[int]bool)
	for _, children := range childrenByParent {
		for _, c := range children {
			childIDSet[c.TypeID] = true
		}
	}

	standalone := make([]model.CategoryDef, 0)
	for _, t := range visible {
		if !parentIDs[t.TypeID] && !childIDSet[t.TypeID] {
			standalone = append(standalone, toDef(t))
		}
	}

	primary := make([]model.CategoryDef, 0, len(parents)+len(standalone))
	for _, p := range parents {
		primary = append(primary, toDef(p))
	}
	primary = append(primary, standalone...)

	return model.CategoryTree{
		All:              all,
		Primary:          primary,
		ChildrenByParent: childrenByParent,
	}
}

func GetCategoryLabel(tree model.CategoryTree, typeID *int) string {
	if typeID == nil {
		return "全部"
	}
	for _, item := range tree.All {
		if item.TypeID == *typeID {
			return item.Label
		}
	}
	return ""
}
