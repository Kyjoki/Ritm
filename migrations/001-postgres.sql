-- Explicitly applied by migrations/migrate.ts. Never run on a function cold start.
CREATE TABLE IF NOT EXISTS ritm_workspace (id INTEGER PRIMARY KEY CHECK (id = 1));
INSERT INTO ritm_workspace (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS ritm_tasks (id UUID PRIMARY KEY, json JSONB NOT NULL);
CREATE TABLE IF NOT EXISTS ritm_deleted_tasks (
  id UUID PRIMARY KEY,
  json JSONB NOT NULL,
  deleted_at BIGINT NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS ritm_conversations (id UUID PRIMARY KEY, json JSONB NOT NULL);
CREATE TABLE IF NOT EXISTS ritm_config (key TEXT PRIMARY KEY, json JSONB NOT NULL);
INSERT INTO ritm_config (key, json) VALUES (
  'settings',
  '{"displayName":"Максим","email":"","theme":"dark","sidebar":"dark","language":"ru","timeZone":"Asia/Qyzylorda","notifications":false,"dailyBriefing":false,"workDayStart":"09:00","workDayEnd":"18:00"}'::jsonb
) ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS ritm_chat_requests (
  id UUID PRIMARY KEY,
  fingerprint TEXT NOT NULL,
  conversation_id UUID REFERENCES ritm_conversations (id) ON DELETE CASCADE,
  status TEXT NOT NULL CHECK (status IN ('running', 'complete')),
  lease_token UUID,
  lease_expires_at BIGINT,
  CHECK ((status = 'running' AND lease_token IS NOT NULL AND lease_expires_at IS NOT NULL)
    OR (status = 'complete' AND lease_token IS NULL AND lease_expires_at IS NULL))
);
CREATE INDEX IF NOT EXISTS ritm_chat_conversation_status ON ritm_chat_requests (conversation_id, status);
CREATE TABLE IF NOT EXISTS ritm_sessions (id_hash TEXT PRIMARY KEY, expires_at BIGINT NOT NULL);
CREATE TABLE IF NOT EXISTS ritm_rate_limits (key TEXT PRIMARY KEY, count INTEGER NOT NULL, expires_at BIGINT NOT NULL);
CREATE TABLE IF NOT EXISTS ritm_server_secrets (name TEXT PRIMARY KEY, ciphertext TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS ritm_leases (name TEXT PRIMARY KEY, token UUID NOT NULL, expires_at BIGINT NOT NULL);
