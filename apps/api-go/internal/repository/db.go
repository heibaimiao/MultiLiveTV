package repository

import (
	"github.com/heibaimiao/multilivetv/api-go/internal/model"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

func Connect(databaseURL string) (*gorm.DB, error) {
	if databaseURL == "" {
		return nil, nil
	}
	db, err := gorm.Open(postgres.Open(databaseURL), &gorm.Config{})
	if err != nil {
		return nil, err
	}
	if err := db.AutoMigrate(
		&model.User{},
		&model.Favorite{},
		&model.WatchProgress{},
		&model.RefreshToken{},
	); err != nil {
		return nil, err
	}
	return db, nil
}
