package unified

import "testing"

func TestFindAndParentSlug(t *testing.T) {
	mu.Lock()
	data = Catalog{
		DefaultSlug: "movie",
		Tree: []Node{
			{
				Slug:  "movie",
				Label: "电影",
				Sources: map[string]int{"33": 1},
				Children: []Node{
					{Slug: "movie-action", Label: "动作片", Sources: map[string]int{"33": 6, "125": 6}},
				},
			},
		},
	}
	mu.Unlock()

	node, ok := Find("movie-action")
	if !ok || node.Label != "动作片" {
		t.Fatalf("find action: %+v ok=%v", node, ok)
	}
	if ParentSlug("movie-action") != "movie" {
		t.Fatalf("parent = %s", ParentSlug("movie-action"))
	}
	maps := SourceTypeIDs(node, []int{33, 999})
	if len(maps) != 1 || maps[0].SourceID != 33 || maps[0].TypeID != 6 {
		t.Fatalf("maps = %+v", maps)
	}
	pub := Public()
	if pub.DefaultSlug != "movie" || len(pub.Tree) != 1 || len(pub.Tree[0].Children) != 1 {
		t.Fatalf("public = %+v", pub)
	}
	if pub.Tree[0].Children[0].Slug != "movie-action" {
		t.Fatalf("public child = %+v", pub.Tree[0].Children[0])
	}
}
