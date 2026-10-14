-- Separate personal finance ledger; values are validated in the authenticated API.
CREATE TABLE IF NOT EXISTS ritm_finance_entries (id UUID PRIMARY KEY, json JSONB NOT NULL);
