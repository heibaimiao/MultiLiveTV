package model

import (
	"time"

	"github.com/google/uuid"
)

type User struct {
	ID           uuid.UUID `gorm:"type:uuid;primaryKey" json:"id"`
	Email        string    `gorm:"uniqueIndex;size:255;not null" json:"email"`
	PasswordHash string    `gorm:"not null" json:"-"`
	CreatedAt    time.Time `json:"created_at"`
}

type Favorite struct {
	ID              uuid.UUID `gorm:"type:uuid;primaryKey" json:"id"`
	UserID          uuid.UUID `gorm:"type:uuid;index;not null;uniqueIndex:idx_user_favorite" json:"user_id"`
	MergeKey        string    `gorm:"size:255;not null;uniqueIndex:idx_user_favorite" json:"merge_key"`
	VodName         string    `gorm:"size:255;not null" json:"vod_name"`
	PrimarySourceID int       `json:"primary_source_id"`
	PrimaryVodID    string    `gorm:"size:64;not null" json:"primary_vod_id"`
	Poster          string    `gorm:"size:512" json:"poster,omitempty"`
	CreatedAt       time.Time `json:"created_at"`
}

type WatchProgress struct {
	ID          uuid.UUID `gorm:"type:uuid;primaryKey" json:"id"`
	UserID      uuid.UUID `gorm:"type:uuid;index;not null" json:"user_id"`
	ProgressKey string    `gorm:"size:255;not null;uniqueIndex:idx_user_progress" json:"progress_key"`
	PositionSec float64   `json:"position_sec"`
	DurationSec float64   `json:"duration_sec"`
	UpdatedAt   time.Time `json:"updated_at"`
}

type RefreshToken struct {
	ID        uuid.UUID `gorm:"type:uuid;primaryKey" json:"id"`
	UserID    uuid.UUID `gorm:"type:uuid;index;not null" json:"user_id"`
	TokenHash string    `gorm:"size:128;not null" json:"-"`
	ExpiresAt time.Time `json:"expires_at"`
	CreatedAt time.Time `json:"created_at"`
}
