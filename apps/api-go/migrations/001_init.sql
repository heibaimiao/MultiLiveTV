-- +goose Up
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS favorites (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    merge_key VARCHAR(255) NOT NULL,
    vod_name VARCHAR(255) NOT NULL,
    primary_source_id INT NOT NULL,
    primary_vod_id VARCHAR(64) NOT NULL,
    poster VARCHAR(512),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    UNIQUE(user_id, merge_key)
);

CREATE TABLE IF NOT EXISTS watch_progress (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    progress_key VARCHAR(255) NOT NULL,
    position_sec DOUBLE PRECISION NOT NULL DEFAULT 0,
    duration_sec DOUBLE PRECISION NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, progress_key)
);
CREATE INDEX IF NOT EXISTS idx_progress_user ON watch_progress(user_id);

CREATE TABLE IF NOT EXISTS refresh_tokens (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(128) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_refresh_user ON refresh_tokens(user_id);

-- +goose Down
DROP TABLE IF EXISTS refresh_tokens;
DROP TABLE IF EXISTS watch_progress;
DROP TABLE IF EXISTS favorites;
DROP TABLE IF EXISTS users;
