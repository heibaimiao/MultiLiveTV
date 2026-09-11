package unified

import (
	"encoding/json"
	"os"
	"sort"
	"strconv"
	"sync"
)

type Node struct {
	Slug     string         `json:"slug"`
	Label    string         `json:"label"`
	Sources  map[string]int `json:"sources"`
	Children []Node         `json:"children,omitempty"`
}

type Catalog struct {
	Version     int               `json:"version"`
	GeneratedAt string            `json:"generated_at"`
	Aliases     map[string]string `json:"aliases"`
	DefaultSlug string            `json:"defaultSlug"`
	Tree        []Node            `json:"tree"`
}

type PublicChild struct {
	Slug  string `json:"slug"`
	Label string `json:"label"`
}

type PublicNode struct {
	Slug     string        `json:"slug"`
	Label    string        `json:"label"`
	Children []PublicChild `json:"children"`
}

type PublicCatalog struct {
	Version     int          `json:"version"`
	DefaultSlug string       `json:"defaultSlug"`
	Tree        []PublicNode `json:"tree"`
}

var (
	mu   sync.RWMutex
	data Catalog
)

func LoadFile(path string) error {
	raw, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	var catalog Catalog
	if err := json.Unmarshal(raw, &catalog); err != nil {
		return err
	}
	if catalog.DefaultSlug == "" {
		catalog.DefaultSlug = "movie"
	}
	mu.Lock()
	data = catalog
	mu.Unlock()
	return nil
}

func Current() Catalog {
	mu.RLock()
	defer mu.RUnlock()
	return data
}

func Public() PublicCatalog {
	c := Current()
	out := PublicCatalog{
		Version:     c.Version,
		DefaultSlug: c.DefaultSlug,
		Tree:        make([]PublicNode, 0, len(c.Tree)),
	}
	for _, node := range c.Tree {
		children := make([]PublicChild, 0, len(node.Children))
		for _, child := range node.Children {
			children = append(children, PublicChild{Slug: child.Slug, Label: child.Label})
		}
		out.Tree = append(out.Tree, PublicNode{
			Slug:     node.Slug,
			Label:    node.Label,
			Children: children,
		})
	}
	return out
}

func Find(slug string) (Node, bool) {
	if slug == "" {
		return Node{}, false
	}
	c := Current()
	for _, node := range c.Tree {
		if node.Slug == slug {
			return node, true
		}
		for _, child := range node.Children {
			if child.Slug == slug {
				return child, true
			}
		}
	}
	return Node{}, false
}

func ParentSlug(slug string) string {
	c := Current()
	for _, node := range c.Tree {
		if node.Slug == slug {
			return node.Slug
		}
		for _, child := range node.Children {
			if child.Slug == slug {
				return node.Slug
			}
		}
	}
	return ""
}

func SourceTypeIDs(node Node, enabledSourceIDs []int) []SourceMapping {
	enabled := make(map[int]struct{}, len(enabledSourceIDs))
	for _, id := range enabledSourceIDs {
		enabled[id] = struct{}{}
	}
	out := make([]SourceMapping, 0, len(node.Sources))
	for sid, typeID := range node.Sources {
		id, err := strconv.Atoi(sid)
		if err != nil {
			continue
		}
		if _, ok := enabled[id]; !ok {
			continue
		}
		out = append(out, SourceMapping{SourceID: id, TypeID: typeID})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].SourceID < out[j].SourceID })
	return out
}

type SourceMapping struct {
	SourceID int
	TypeID   int
}
