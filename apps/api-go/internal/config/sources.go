package config

import (
	"encoding/json"
	"os"
	"sync"

	"github.com/heibaimiao/multilivetv/api-go/internal/model"
)

type SourceStore struct {
	mu      sync.RWMutex
	sources []model.Source
}

func NewSourceStore(path string) (*SourceStore, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var sources []model.Source
	if err := json.Unmarshal(data, &sources); err != nil {
		return nil, err
	}
	return &SourceStore{sources: sources}, nil
}

func (s *SourceStore) All() []model.Source {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]model.Source, len(s.sources))
	copy(out, s.sources)
	return out
}

func (s *SourceStore) Enabled() []model.Source {
	all := s.All()
	out := make([]model.Source, 0, len(all))
	for _, src := range all {
		if src.Flag == 0 && !src.VipOnly {
			out = append(out, src)
		}
	}
	return out
}

func (s *SourceStore) ByID(id int) *model.Source {
	for _, src := range s.Enabled() {
		if src.ID == id {
			copy := src
			return &copy
		}
	}
	return nil
}

func NewEmptySourceStore() *SourceStore {
	return &SourceStore{sources: nil}
}

func (s *SourceStore) Default() *model.Source {
	enabled := s.Enabled()
	if len(enabled) == 0 {
		return nil
	}
	copy := enabled[0]
	return &copy
}
