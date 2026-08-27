package handler

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/heibaimiao/multilivetv/api-go/internal/config"
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
