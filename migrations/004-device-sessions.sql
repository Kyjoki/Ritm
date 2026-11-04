-- Device sessions: client, device name and activity for each owner session.
-- Two-factor state lives in encrypted server secrets and needs no schema change.
ALTER TABLE ritm_sessions ADD COLUMN IF NOT EXISTS client TEXT NOT NULL DEFAULT 'web';
ALTER TABLE ritm_sessions ADD COLUMN IF NOT EXISTS device_name TEXT NOT NULL DEFAULT '';
ALTER TABLE ritm_sessions ADD COLUMN IF NOT EXISTS created_at BIGINT NOT NULL DEFAULT 0;
ALTER TABLE ritm_sessions ADD COLUMN IF NOT EXISTS last_seen_at BIGINT NOT NULL DEFAULT 0;
ALTER TABLE ritm_sessions ADD COLUMN IF NOT EXISTS absolute_expires_at BIGINT NOT NULL DEFAULT 0;
