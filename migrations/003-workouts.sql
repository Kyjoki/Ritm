-- Owner workouts shared by iPhone, web and desktop; data is opaque JSON validated by the API.
CREATE TABLE IF NOT EXISTS workout_programs (
  id TEXT PRIMARY KEY,
  data JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS workout_sessions (
  id TEXT PRIMARY KEY,
  data JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS workout_sessions_updated_at ON workout_sessions (updated_at DESC);
