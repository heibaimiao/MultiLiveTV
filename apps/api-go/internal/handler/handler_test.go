package handler

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/heibaimiao/multilivetv/api-go/internal/config"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/bpz5"
)

func TestGetSources(t *testing.T) {
	gin.SetMode(gin.TestMode)
	store := config.NewEmptySourceStore()
	h := New(store)

	r := gin.New()
	r.GET("/sources", h.GetSources)

	req := httptest.NewRequest(http.MethodGet, "/sources", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}
}

func TestSearchVod_MissingKeyword(t *testing.T) {
	gin.SetMode(gin.TestMode)
	h := New(config.NewEmptySourceStore())
	r := gin.New()
	r.GET("/search", h.SearchVod)

	req := httptest.NewRequest(http.MethodGet, "/search", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestResolvePlay_TicketNotEnabled(t *testing.T) {
	gin.SetMode(gin.TestMode)
	h := New(config.NewEmptySourceStore())
	r := gin.New()
	r.POST("/play/resolve", h.ResolvePlay)

	req := httptest.NewRequest(http.MethodPost, "/play/resolve", strings.NewReader(`{"mode":"ticket","ticket":"rpt1-x"}`))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusNotImplemented {
		t.Fatalf("expected 501, got %d body=%s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "ticket_not_enabled") {
		t.Fatalf("body = %s", w.Body.String())
	}
}

func TestResolvePlay_TicketViaMockUpstream(t *testing.T) {
	gin.SetMode(gin.TestMode)
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusCreated)
		_, _ = w.Write([]byte(`{"line":{"url":"https://cdn.example/ok.m3u8","url_kind":"m3u8"}}`))
	}))
	defer upstream.Close()

	client := bpz5.New(upstream.URL, "secret")
	client.HTTP = upstream.Client()
	h := NewWithBPZ5(config.NewEmptySourceStore(), client)
	r := gin.New()
	r.POST("/play/resolve", h.ResolvePlay)

	req := httptest.NewRequest(http.MethodPost, "/play/resolve", strings.NewReader(`{"mode":"ticket","url":"resolve://rpt1.abc"}`))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "https://cdn.example/ok.m3u8") {
		t.Fatalf("body = %s", w.Body.String())
	}
	if !strings.Contains(w.Body.String(), `"mode":"ticket"`) {
		t.Fatalf("body missing mode ticket: %s", w.Body.String())
	}
}

func TestResolvePlay_DirectWithoutSource(t *testing.T) {
	gin.SetMode(gin.TestMode)
	h := New(config.NewEmptySourceStore())
	r := gin.New()
	r.POST("/play/resolve", h.ResolvePlay)

	req := httptest.NewRequest(http.MethodPost, "/play/resolve", strings.NewReader(`{"mode":"direct","url":"https://cdn.example/a.m3u8","jx":false}`))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "https://cdn.example/a.m3u8") {
		t.Fatalf("body = %s", w.Body.String())
	}
}
