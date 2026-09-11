package main

import (
	"log"
	"os"

	"github.com/gin-gonic/gin"
	swaggerFiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"
	"github.com/heibaimiao/multilivetv/api-go/internal/config"
	"github.com/heibaimiao/multilivetv/api-go/internal/handler"
	"github.com/heibaimiao/multilivetv/api-go/internal/middleware"
	"github.com/heibaimiao/multilivetv/api-go/internal/repository"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/admin"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/auth"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/bpz5"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/parser"
	"github.com/heibaimiao/multilivetv/api-go/internal/service/unified"
)

func main() {
	cfg := config.Load()

	sources, err := config.NewSourceStore(cfg.SourcesPath)
	if err != nil {
		log.Fatalf("load sources: %v", err)
	}
	if err := parser.LoadWeightsFile(cfg.WeightsPath); err != nil {
		log.Printf("play-line-weights: using defaults (%v)", err)
	}
	if err := unified.LoadFile(cfg.CategoriesPath); err != nil {
		log.Printf("unified-categories: unavailable (%v)", err)
	}

	db, err := repository.Connect(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("database: %v", err)
	}

	requestLog := middleware.NewRequestLogBuffer(200)

	r := gin.Default()
	r.Use(middleware.CORSWithOrigin(cfg.AdminCORSOrigin))
	r.Use(middleware.RequestLogger(requestLog))

	h := handler.NewWithBPZ5(sources, bpz5.New(cfg.BPZ5BaseURL, cfg.BPZ5HMACSecret))
	if cfg.BPZ5HMACSecret == "" {
		log.Println("BPZ5_HMAC_SECRET not set — play/resolve ticket mode disabled")
	}

	v1 := r.Group("/api/v1")
	{
		v1.GET("/sources", h.GetSources)
		v1.GET("/vod/list", h.GetVodList)
		v1.GET("/vod/detail", h.GetVodDetail)
		v1.GET("/vod/search", h.SearchVod)
		v1.GET("/vod/types", h.GetVodTypes)
		v1.GET("/vod/categories", h.GetUnifiedCategories)
		v1.GET("/vod/pic", h.GetVodPic)
		v1.GET("/play/parse", h.ParsePlay)
		v1.POST("/play/resolve", h.ResolvePlay)

		if db != nil {
			authSvc := auth.NewService(db, cfg.JWTSecret)
			ah := &handler.AuthHandler{Auth: authSvc, DB: db}

			authGroup := v1.Group("/auth")
			{
				authGroup.POST("/register", ah.Register)
				authGroup.POST("/login", ah.Login)
				authGroup.POST("/refresh", ah.Refresh)
			}

			userGroup := v1.Group("/user")
			userGroup.Use(middleware.JWT(authSvc))
			{
				userGroup.GET("/favorites", ah.ListFavorites)
				userGroup.POST("/favorites", ah.AddFavorite)
				userGroup.DELETE("/favorites", ah.DeleteFavorite)
				userGroup.GET("/progress", ah.GetProgress)
				userGroup.PUT("/progress", ah.PutProgress)
			}
		} else {
			log.Println("DATABASE_URL not set — auth routes disabled")
		}

		if cfg.AdminEnabled() {
			adminSvc := admin.NewService(cfg.AdminUsername, cfg.AdminPassword, cfg.AdminJWTSecret)
			adminH := &handler.AdminHandler{
				Auth:       adminSvc,
				Sources:    sources,
				Category:   h.Category,
				DB:         db,
				RequestLog: requestLog,
			}
			adminGroup := v1.Group("/admin")
			adminGroup.POST("/login", adminH.Login)
			protected := adminGroup.Group("")
			protected.Use(middleware.AdminJWT(adminSvc))
			{
				protected.GET("/sources", adminH.ListSources)
				protected.POST("/sources", adminH.CreateSource)
				protected.PUT("/sources/:id", adminH.UpdateSource)
				protected.DELETE("/sources/:id", adminH.DeleteSource)
				protected.POST("/sources/:id/test", adminH.TestSource)

				protected.GET("/users", adminH.ListUsers)
				protected.GET("/users/stats", adminH.UserStats)
				protected.DELETE("/users/:id", adminH.DeleteUser)

				protected.GET("/system/status", adminH.SystemStatus)
				protected.POST("/system/cache/clear", adminH.ClearCache)
				protected.GET("/system/logs", adminH.ListLogs)
			}
		} else {
			log.Println("ADMIN_USERNAME/ADMIN_PASSWORD not set — admin routes disabled")
		}
	}

	r.GET("/health", handler.Health(db))
	r.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))

	addr := ":" + cfg.Port
	log.Printf("listening on %s", addr)
	if err := r.Run(addr); err != nil {
		log.Fatal(err)
	}
}

func init() {
	if _, err := os.Stat("config/sources.json"); err != nil {
		_ = os.Chdir("apps/api-go")
	}
}
