package config

import (
	"encoding/json"
	"fmt"
	"os"
	"sync"

	"github.com/heibaimiao/multilivetv/api-go/internal/model"
)

type SourceStore struct {
	mu       sync.RWMutex
	sources  []model.Source
	filePath string
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
	return &SourceStore{sources: sources, filePath: path}, nil
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

func (s *SourceStore) ByIDAdmin(id int) *model.Source {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, src := range s.sources {
		if src.ID == id {
			copy := src
			return &copy
		}
	}
	return nil
}

func (s *SourceStore) SaveAll(sources []model.Source) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.filePath == "" {
		return fmt.Errorf("sources file path not set")
	}
	data, err := json.MarshalIndent(sources, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	if err := os.WriteFile(s.filePath, data, 0o644); err != nil {
		return err
	}
	s.sources = sources
	return nil
}

func (s *SourceStore) Upsert(source model.Source) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	found := false
	for i, src := range s.sources {
		if src.ID == source.ID {
			s.sources[i] = source
			found = true
			break
		}
	}
	if !found {
		s.sources = append(s.sources, source)
	}
	return s.persistLocked()
}

func (s *SourceStore) Delete(id int) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]model.Source, 0, len(s.sources))
	found := false
	for _, src := range s.sources {
		if src.ID == id {
			found = true
			continue
		}
		out = append(out, src)
	}
	if !found {
		return fmt.Errorf("source not found")
	}
	s.sources = out
	return s.persistLocked()
}

func (s *SourceStore) SetFlag(id int, flag int) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i, src := range s.sources {
		if src.ID == id {
			s.sources[i].Flag = flag
			return s.persistLocked()
		}
	}
	return fmt.Errorf("source not found")
}

func (s *SourceStore) persistLocked() error {
	if s.filePath == "" {
		return fmt.Errorf("sources file path not set")
	}
	data, err := json.MarshalIndent(s.sources, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	if err := os.WriteFile(s.filePath, data, 0o644); err != nil {
		return err
	}
	return nil
}

func (s *SourceStore) Count() (total int, enabled int) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	total = len(s.sources)
	for _, src := range s.sources {
		if src.Flag == 0 && !src.VipOnly {
			enabled++
		}
	}
	return total, enabled
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
