-- ============================================================
-- Autonomous B2B Revenue Acceleration Engine
-- schema.sql — Neon PostgreSQL (serverless, SSL required)
-- Apply: psql "$DATABASE_URL" -f schema.sql
-- ============================================================

BEGIN;

DROP TABLE IF EXISTS commercial_deals;
DROP TABLE IF EXISTS accounts_and_leads;

-- ------------------------------------------------------------
-- accounts_and_leads
-- One row per enriched account/lead landing from HubSpot via Make.com.
-- icp_score and bdr_ai_snippet are produced by the Claude module.
-- ------------------------------------------------------------
CREATE TABLE accounts_and_leads (
    lead_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_name    VARCHAR(120)  NOT NULL,
    industry        VARCHAR(60)   NOT NULL,
    employee_count  INTEGER       NOT NULL CHECK (employee_count > 0),
    icp_score       NUMERIC(5,2)  NOT NULL CHECK (icp_score BETWEEN 0 AND 100),
    bdr_ai_snippet  TEXT,                       -- Claude-generated 2-sentence outreach hook
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------
-- commercial_deals
-- Transaction log of deals attached to accounts.
-- expansion_signal_score (0-100) blends usage/health signals for KAM plays.
-- win_probability stored as decimal fraction (0.00-1.00) for weighted ARR math.
-- ------------------------------------------------------------
CREATE TABLE commercial_deals (
    deal_id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_id              BIGINT        NOT NULL
                            REFERENCES accounts_and_leads (lead_id) ON DELETE CASCADE,
    deal_stage              VARCHAR(30)   NOT NULL CHECK (deal_stage IN
                              ('Discovery','Qualification','Proposal',
                               'Negotiation','Closed Won','Closed Lost')),
    contract_tier           VARCHAR(20)   NOT NULL CHECK (contract_tier IN
                              ('Starter','Growth','Scale','Enterprise')),
    arr_value               NUMERIC(12,2) NOT NULL CHECK (arr_value >= 0),
    win_probability         NUMERIC(4,3)  NOT NULL CHECK (win_probability BETWEEN 0 AND 1),
    expansion_signal_score  NUMERIC(5,2)  NOT NULL CHECK (expansion_signal_score BETWEEN 0 AND 100),
    close_date              DATE,          -- NULL while deal is open
    created_at              TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- Indexes tuned for the Phase 2 analytics workload
CREATE INDEX idx_leads_icp          ON accounts_and_leads (icp_score DESC);
CREATE INDEX idx_leads_industry     ON accounts_and_leads (industry);
CREATE INDEX idx_deals_account      ON commercial_deals (account_id);
CREATE INDEX idx_deals_stage        ON commercial_deals (deal_stage);
CREATE INDEX idx_deals_tier_stage   ON commercial_deals (contract_tier, deal_stage);
CREATE INDEX idx_deals_expansion    ON commercial_deals (expansion_signal_score DESC)
    WHERE deal_stage = 'Closed Won';

COMMENT ON TABLE  accounts_and_leads IS 'Enriched leads/accounts from HubSpot via Make.com + Claude ICP scoring';
COMMENT ON TABLE  commercial_deals   IS 'Deal transaction log powering pipeline velocity and expansion analytics';
COMMENT ON COLUMN commercial_deals.win_probability IS 'Decimal fraction 0-1; multiply by arr_value for weighted pipeline';

COMMIT;
