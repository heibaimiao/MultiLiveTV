package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/heibaimiao/multilivetv/api-go/internal/config"
	"github.com/heibaimiao/multilivetv/api-go/internal/middleware"
	"github.com/heibaimiao/multilivetv/api-go/internal/model"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/admin"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/category"
)

func TestAdminLoginAndSources(t *testing.T) {
	gin.SetMode(gin.TestMode)
	tmp := filepath.Join(t.TempDir(), "sources.json")
	_ = os.WriteFile(tmp, []byte("[]"), 0o644)
	store, err := config.NewSourceStore(tmp)
	if err != nil {
		t.Fatal(err)
	}
	adminSvc := admin.NewService("admin", "secret", "test-secret")
	cache := category.NewCache()
	logBuf := middleware.NewRequestLogBuffer(10)
	ah := &AdminHandler{
		Auth:       adminSvc,
		Sources:    store,
		Category:   cache,
		RequestLog: logBuf,
	}

	r := gin.New()
	r.POST("/admin/login", ah.Login)
	r.GET("/admin/sources", middleware.AdminJWT(adminSvc), ah.ListSources)
	r.POST("/admin/sources", middleware.AdminJWT(adminSvc), ah.CreateSource)
	r.POST("/admin/system/cache/clear", middleware.AdminJWT(adminSvc), ah.ClearCache)

	loginBody := `{"username":"admin","password":"secret"}`
	req := httptest.NewRequest(http.MethodPost, "/admin/login", bytes.NewBufferString(loginBody))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("login status %d: %s", w.Code, w.Body.String())
	}
	var loginResp struct {
		AccessToken string `json:"access_token"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &loginResp); err != nil {
		t.Fatal(err)
	}

	createBody := `{"id":999,"name":"test","url":"https://example.com/api.php/provide/vod/","flag":0}`
	req = httptest.NewRequest(http.MethodPost, "/admin/sources", bytes.NewBufferString(createBody))
	req.Header.Set("Authorization", "Bearer "+loginResp.AccessToken)
	w = httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("create status %d: %s", w.Code, w.Body.String())
	}

	req = httptest.NewRequest(http.MethodGet, "/admin/sources", nil)
	req.Header.Set("Authorization", "Bearer "+loginResp.AccessToken)
	w = httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("list status %d", w.Code)
	}

	req = httptest.NewRequest(http.MethodPost, "/admin/system/cache/clear", nil)
	req.Header.Set("Authorization", "Bearer "+loginResp.AccessToken)
	w = httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("cache clear status %d", w.Code)
	}
}
func TestSourceStoreUpsertDelete(t *testing.T) {
	tmp := filepath.Join(t.TempDir(), "sources.json")
	_ = os.WriteFile(tmp, []byte("[]"), 0o644)
	store, err := config.NewSourceStore(tmp)
	if err != nil {
		t.Fatal(err)
	}
	src := model.Source{ID: 1, Name: "a", URL: "http://x", Flag: 0}
	if err := store.Upsert(src); err != nil {
		t.Fatal(err)
	}
	if store.ByIDAdmin(1) == nil {
		t.Fatal("expected source")
	}
	if err := store.Delete(1); err != nil {
		t.Fatal(err)
	}
	if store.ByIDAdmin(1) != nil {
		t.Fatal("expected deleted")
	}
}
