package middleware

import (
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/admin"
)

func AdminJWT(svc *admin.Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		if header == "" || !strings.HasPrefix(header, "Bearer ") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing token"})
			return
		}
		token := strings.TrimPrefix(header, "Bearer ")
		claims, err := svc.ParseToken(token)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
			return
		}
		c.Set("adminUsername", claims.Username)
		c.Next()
	}
}

type RequestLogEntry struct {
	Time    time.Time `json:"time"`
	Method  string    `json:"method"`
	Path    string    `json:"path"`
	Status  int       `json:"status"`
	Latency string    `json:"latency"`
}

type RequestLogBuffer struct {
	mu      sync.RWMutex
	entries []RequestLogEntry
	max     int
}

func NewRequestLogBuffer(max int) *RequestLogBuffer {
	return &RequestLogBuffer{max: max, entries: make([]RequestLogEntry, 0, max)}
}

func (b *RequestLogBuffer) Add(entry RequestLogEntry) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if len(b.entries) >= b.max {
		b.entries = b.entries[1:]
	}
	b.entries = append(b.entries, entry)
}

func (b *RequestLogBuffer) List() []RequestLogEntry {
	b.mu.RLock()
	defer b.mu.RUnlock()
	out := make([]RequestLogEntry, len(b.entries))
	copy(out, b.entries)
	return out
}

func RequestLogger(buf *RequestLogBuffer) gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		c.Next()
		buf.Add(RequestLogEntry{
			Time:    start,
			Method:  c.Request.Method,
			Path:    c.Request.URL.Path,
			Status:  c.Writer.Status(),
			Latency: time.Since(start).String(),
		})
	}
}

func CORSWithOrigin(defaultOrigin string) gin.HandlerFunc {
	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		if origin == "" {
			origin = defaultOrigin
		}
		if origin != "" {
			c.Header("Access-Control-Allow-Origin", origin)
		} else {
			c.Header("Access-Control-Allow-Origin", "*")
		}
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Authorization")
		c.Header("Access-Control-Allow-Credentials", "true")
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}
