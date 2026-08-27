package handler

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/heibaimiao/multilivetv/api-go/internal/model"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/auth"
	"gorm.io/gorm"
)

type AuthHandler struct {
	Auth *auth.Service
	DB   *gorm.DB
}

type registerRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=6"`
}

type loginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

func (h *AuthHandler) Register(c *gin.Context) {
	var req registerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	user, err := h.Auth.Register(req.Email, req.Password)
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "email already registered"})
		return
	}
	_, tokens, err := h.Auth.Login(req.Email, req.Password)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, gin.H{
		"user":   gin.H{"id": user.ID, "email": user.Email},
		"tokens": tokens,
	})
}

func (h *AuthHandler) Login(c *gin.Context) {
	var req loginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	user, tokens, err := h.Auth.Login(req.Email, req.Password)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"user":   gin.H{"id": user.ID, "email": user.Email},
		"tokens": tokens,
	})
}

func (h *AuthHandler) Refresh(c *gin.Context) {
	var req refreshRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	tokens, err := h.Auth.Refresh(req.RefreshToken)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, tokens)
}

type favoriteRequest struct {
	MergeKey        string `json:"merge_key" binding:"required"`
	VodName         string `json:"vod_name" binding:"required"`
	PrimarySourceID int    `json:"primary_source_id" binding:"required"`
	PrimaryVodID    string `json:"primary_vod_id" binding:"required"`
	Poster          string `json:"poster"`
}

func (h *AuthHandler) ListFavorites(c *gin.Context) {
	userID := c.GetString("userID")
	var favorites []model.Favorite
	if err := h.DB.Where("user_id = ?", userID).Order("created_at desc").Find(&favorites).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"favorites": favorites})
}

func (h *AuthHandler) AddFavorite(c *gin.Context) {
	userID := c.GetString("userID")
	uid, err := uuid.Parse(userID)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid user"})
		return
	}
	var req favoriteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	var existing model.Favorite
	if err := h.DB.Where("user_id = ? AND merge_key = ?", uid, req.MergeKey).First(&existing).Error; err == nil {
		c.JSON(http.StatusOK, existing)
		return
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	fav := model.Favorite{
		ID:              uuid.New(),
		UserID:          uid,
		MergeKey:        req.MergeKey,
		VodName:         req.VodName,
		PrimarySourceID: req.PrimarySourceID,
		PrimaryVodID:    req.PrimaryVodID,
		Poster:          req.Poster,
	}
	if err := h.DB.Create(&fav).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, fav)
}

func (h *AuthHandler) DeleteFavorite(c *gin.Context) {
	userID := c.GetString("userID")
	mergeKey := c.Query("merge_key")
	if mergeKey == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "merge_key is required"})
		return
	}
	if err := h.DB.Where("user_id = ? AND merge_key = ?", userID, mergeKey).Delete(&model.Favorite{}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

type progressRequest struct {
	ProgressKey  string  `json:"progress_key" binding:"required"`
	PositionSec  float64 `json:"position_sec"`
	DurationSec  float64 `json:"duration_sec"`
}

func (h *AuthHandler) GetProgress(c *gin.Context) {
	userID := c.GetString("userID")
	key := c.Query("progress_key")
	q := h.DB.Where("user_id = ?", userID)
	if key != "" {
		q = q.Where("progress_key = ?", key)
	}
	var items []model.WatchProgress
	if err := q.Find(&items).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"progress": items})
}

func (h *AuthHandler) PutProgress(c *gin.Context) {
	userID := c.GetString("userID")
	uid, err := uuid.Parse(userID)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid user"})
		return
	}
	var req progressRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var existing model.WatchProgress
	err = h.DB.Where("user_id = ? AND progress_key = ?", userID, req.ProgressKey).First(&existing).Error
	if err == nil {
		existing.PositionSec = req.PositionSec
		existing.DurationSec = req.DurationSec
		if err := h.DB.Save(&existing).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, existing)
		return
	}

	item := model.WatchProgress{
		ID:          uuid.New(),
		UserID:      uid,
		ProgressKey: req.ProgressKey,
		PositionSec: req.PositionSec,
		DurationSec: req.DurationSec,
	}
	if err := h.DB.Create(&item).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, item)
}
