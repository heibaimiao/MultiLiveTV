// Package main MultiLiveTV API server.
//
//	@title			MultiLiveTV API
//	@version		1.0
//	@description	VOD aggregation API for MultiLiveTV native clients
//	@host			localhost:8080
//	@BasePath		/api/v1
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
	"github.com/heibaimiao/multilivetv/api-go/internal/service/auth"
)

func main() {
	cfg := config.Load()

	sources, err := config.NewSourceStore(cfg.SourcesPath)
	if err != nil {
		log.Fatalf("load sources: %v", err)
	}

	db, err := repository.Connect(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("database: %v", err)
	}

	r := gin.Default()
	r.Use(middleware.CORS())

	h := handler.New(sources)

	v1 := r.Group("/api/v1")
	{
		v1.GET("/sources", h.GetSources)
		v1.GET("/vod/list", h.GetVodList)
		v1.GET("/vod/detail", h.GetVodDetail)
		v1.GET("/vod/search", h.SearchVod)
		v1.GET("/vod/types", h.GetVodTypes)
		v1.GET("/vod/pic", h.GetVodPic)
		v1.GET("/play/parse", h.ParsePlay)

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
	}

	r.GET("/health", handler.Health(db))
	r.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))

	addr := ":" + cfg.Port
	log.Printf("listening on %s", addr)
	if err := r.Run(addr); err != nil {
		log.Fatal(err)
	}
}

// resolve working directory for sources in dev
func init() {
	if _, err := os.Stat("config/sources.json"); err != nil {
		_ = os.Chdir("apps/api-go")
	}
}
