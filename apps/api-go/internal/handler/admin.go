package handler

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/heibaimiao/multilivetv/api-go/internal/config"
	"github.com/heibaimiao/multilivetv/api-go/internal/middleware"
	"github.com/heibaimiao/multilivetv/api-go/internal/model"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/admin"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/category"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/maccms"
	"gorm.io/gorm"
)

var serverStartTime = time.Now()

type AdminHandler struct {
	Auth       *admin.Service
	Sources    *config.SourceStore
	Category   *category.Cache
	DB         *gorm.DB
	RequestLog *middleware.RequestLogBuffer
}

type adminLoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

func (h *AdminHandler) Login(c *gin.Context) {
	var req adminLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	result, err := h.Auth.Login(req.Username, req.Password)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, result)
}

func (h *AdminHandler) ListSources(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"sources": h.Sources.All()})
}

func (h *AdminHandler) CreateSource(c *gin.Context) {
	var source model.Source
	if err := c.ShouldBindJSON(&source); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if source.ID == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "id is required"})
		return
	}
	if h.Sources.ByIDAdmin(source.ID) != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "source id already exists"})
		return
	}
	if err := h.Sources.Upsert(source); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, source)
}

func (h *AdminHandler) UpdateSource(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	if h.Sources.ByIDAdmin(id) == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "source not found"})
		return
	}
	var source model.Source
	if err := c.ShouldBindJSON(&source); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	source.ID = id
	if err := h.Sources.Upsert(source); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, source)
}

func (h *AdminHandler) DeleteSource(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	if err := h.Sources.Delete(id); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

func (h *AdminHandler) TestSource(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	source := h.Sources.ByIDAdmin(id)
	if source == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "source not found"})
		return
	}
	start := time.Now()
	_, err = maccms.FetchVodTypes(*source)
	latency := time.Since(start)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{
			"ok":      false,
			"latency": latency.String(),
			"error":   err.Error(),
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"ok":      true,
		"latency": latency.String(),
	})
}

type userListItem struct {
	ID            string    `json:"id"`
	Email         string    `json:"email"`
	CreatedAt     time.Time `json:"created_at"`
	FavoriteCount int64     `json:"favorite_count"`
}

func (h *AdminHandler) ListUsers(c *gin.Context) {
	if h.DB == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "database not configured"})
		return
	}
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	if page < 1 {
		page = 1
	}
	pageSize := 20
	offset := (page - 1) * pageSize

	var users []model.User
	if err := h.DB.Order("created_at desc").Offset(offset).Limit(pageSize).Find(&users).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	items := make([]userListItem, 0, len(users))
	for _, user := range users {
		var favCount int64
		_ = h.DB.Model(&model.Favorite{}).Where("user_id = ?", user.ID).Count(&favCount)
		items = append(items, userListItem{
			ID:            user.ID.String(),
			Email:         user.Email,
			CreatedAt:     user.CreatedAt,
			FavoriteCount: favCount,
		})
	}

	var total int64
	_ = h.DB.Model(&model.User{}).Count(&total)
	c.JSON(http.StatusOK, gin.H{
		"users": items,
		"page":  page,
		"total": total,
	})
}

func (h *AdminHandler) UserStats(c *gin.Context) {
	if h.DB == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "database not configured"})
		return
	}
	var totalUsers int64
	_ = h.DB.Model(&model.User{}).Count(&totalUsers)

	today := time.Now().Truncate(24 * time.Hour)
	var todayNew int64
	_ = h.DB.Model(&model.User{}).Where("created_at >= ?", today).Count(&todayNew)

	var totalFavorites int64
	_ = h.DB.Model(&model.Favorite{}).Count(&totalFavorites)

	c.JSON(http.StatusOK, gin.H{
		"total_users":     totalUsers,
		"today_new_users": todayNew,
		"total_favorites": totalFavorites,
	})
}

func (h *AdminHandler) DeleteUser(c *gin.Context) {
	if h.DB == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "database not configured"})
		return
	}
	uid, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user id"})
		return
	}
	if err := h.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("user_id = ?", uid).Delete(&model.Favorite{}).Error; err != nil {
			return err
		}
		if err := tx.Where("user_id = ?", uid).Delete(&model.WatchProgress{}).Error; err != nil {
			return err
		}
		if err := tx.Where("user_id = ?", uid).Delete(&model.RefreshToken{}).Error; err != nil {
			return err
		}
		return tx.Delete(&model.User{}, "id = ?", uid).Error
	}); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

func (h *AdminHandler) SystemStatus(c *gin.Context) {
	total, enabled := h.Sources.Count()
	status := gin.H{
		"uptime":       time.Since(serverStartTime).String(),
		"sources":      total,
		"sources_live": enabled,
		"cache_items":  h.Category.Count(),
	}
	if h.DB != nil {
		sqlDB, err := h.DB.DB()
		if err != nil {
			status["db"] = "error"
		} else if err := sqlDB.Ping(); err != nil {
			status["db"] = "down"
		} else {
			status["db"] = "ok"
		}
	} else {
		status["db"] = "disabled"
	}
	c.JSON(http.StatusOK, status)
}

func (h *AdminHandler) ClearCache(c *gin.Context) {
	h.Category.Clear()
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

func (h *AdminHandler) ListLogs(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"logs": h.RequestLog.List()})
}
