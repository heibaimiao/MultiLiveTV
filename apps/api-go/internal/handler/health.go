package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

func Health(db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		status := gin.H{"status": "ok"}
		if db != nil {
			sqlDB, err := db.DB()
			if err != nil {
				c.JSON(http.StatusServiceUnavailable, gin.H{"status": "error", "db": err.Error()})
				return
			}
			if err := sqlDB.Ping(); err != nil {
				c.JSON(http.StatusServiceUnavailable, gin.H{"status": "error", "db": err.Error()})
				return
			}
			status["db"] = "ok"
		} else {
			status["db"] = "disabled"
		}
		c.JSON(http.StatusOK, status)
	}
}
