-- ============================================================
-- analytics_queries.sql — Phase 2 Advanced SQL Analytics
-- Autonomous B2B Revenue Acceleration Engine (Neon PostgreSQL)
-- These three queries feed the Power BI model directly.
-- ============================================================

-- ------------------------------------------------------------
-- QUERY A: Pipeline Velocity by Company Size
-- Average days-to-close for closed deals, plus average days-in-
-- stage for open deals, bucketed by company size. Note: schema
-- stores current stage only, so open-deal "stage age" is measured
-- from deal creation — a documented approximation.
-- ------------------------------------------------------------
WITH sized_deals AS (
    SELECT
        d.deal_id,
        d.deal_stage,
        d.arr_value,
        d.created_at,
        d.close_date,
        CASE
            WHEN a.employee_count <= 50   THEN '1. SMB (≤50)'
            WHEN a.employee_count <= 200  THEN '2. Mid-Market (51-200)'
            WHEN a.employee_count <= 1000 THEN '3. Growth (201-1000)'
            ELSE                               '4. Enterprise (1000+)'
        END AS company_size_bracket
    FROM commercial_deals d
    JOIN accounts_and_leads a ON a.lead_id = d.account_id
),
closed_velocity AS (
    SELECT
        company_size_bracket,
        COUNT(*)                                                    AS closed_deals,
        ROUND(AVG(close_date - created_at::date), 1)                AS avg_days_to_close,
        ROUND(SUM(arr_value) FILTER (WHERE deal_stage = 'Closed Won')
              / NULLIF(AVG(close_date - created_at::date), 0), 0)   AS won_arr_per_cycle_day
    FROM sized_deals
    WHERE close_date IS NOT NULL
    GROUP BY company_size_bracket
),
open_stage_age AS (
    SELECT
        company_size_bracket,
        deal_stage,
        COUNT(*)                                              AS open_deals,
        -- Ages measured against the reporting snapshot (FY26 Q2 close),
        -- matching seed_data.py's SNAPSHOT anchor, so results are stable.
        ROUND(AVG(EXTRACT(EPOCH FROM (TIMESTAMPTZ '2026-07-01 00:00:00+00' - created_at)) / 86400), 1) AS avg_days_in_pipeline
    FROM sized_deals
    WHERE close_date IS NULL
    GROUP BY company_size_bracket, deal_stage
)
SELECT
    cv.company_size_bracket,
    cv.closed_deals,
    cv.avg_days_to_close,
    cv.won_arr_per_cycle_day        AS pipeline_velocity_eur_per_day,
    osa.deal_stage                  AS open_stage,
    osa.open_deals,
    osa.avg_days_in_pipeline
FROM closed_velocity cv
LEFT JOIN open_stage_age osa USING (company_size_bracket)
ORDER BY cv.company_size_bracket,
         array_position(ARRAY['Discovery','Qualification','Proposal','Negotiation'],
                        osa.deal_stage);


-- ------------------------------------------------------------
-- QUERY B: KAM Expansion Readiness
-- Ranks existing (Closed Won) accounts on lower contract tiers
-- with expansion/health signal > 80, by ARR expansion potential
-- (uplift to the midpoint of the next tier).
-- ------------------------------------------------------------
WITH tier_targets (contract_tier, tier_rank, next_tier_midpoint) AS (
    VALUES ('Starter', 1, 39000.00),   -- Growth midpoint
           ('Growth',  2, 105000.00),  -- Scale midpoint
           ('Scale',   3, 315000.00)   -- Enterprise midpoint
),
won_accounts AS (
    SELECT
        a.lead_id,
        a.company_name,
        a.industry,
        a.employee_count,
        a.icp_score,
        d.contract_tier,
        d.arr_value            AS current_arr,
        d.expansion_signal_score,
        d.close_date
    FROM commercial_deals d
    JOIN accounts_and_leads a ON a.lead_id = d.account_id
    WHERE d.deal_stage = 'Closed Won'
      AND d.contract_tier IN ('Starter', 'Growth', 'Scale')
      AND d.expansion_signal_score > 80
)
SELECT
    RANK() OVER (ORDER BY (t.next_tier_midpoint - w.current_arr)
                          * (w.expansion_signal_score / 100.0) DESC) AS expansion_rank,
    w.company_name,
    w.industry,
    w.contract_tier                                   AS current_tier,
    ROUND(w.current_arr, 0)                           AS current_arr,
    w.expansion_signal_score                          AS health_score,
    ROUND(t.next_tier_midpoint - w.current_arr, 0)    AS arr_expansion_potential,
    ROUND((t.next_tier_midpoint - w.current_arr)
          * (w.expansion_signal_score / 100.0), 0)    AS weighted_expansion_value,
    w.close_date                                      AS customer_since
FROM won_accounts w
JOIN tier_targets t USING (contract_tier)
WHERE t.next_tier_midpoint > w.current_arr
ORDER BY expansion_rank
LIMIT 25;


-- ------------------------------------------------------------
-- QUERY C: Win Rate & Tier Elasticity
-- Win/loss percentages across contract tiers and deal-size
-- brackets — reveals where pricing tiers convert vs. stall.
-- ------------------------------------------------------------
WITH closed AS (
    SELECT
        contract_tier,
        CASE
            WHEN arr_value < 25000  THEN '1. <€25K'
            WHEN arr_value < 75000  THEN '2. €25K-€75K'
            WHEN arr_value < 150000 THEN '3. €75K-€150K'
            ELSE                         '4. €150K+'
        END AS deal_size_bracket,
        deal_stage,
        arr_value
    FROM commercial_deals
    WHERE deal_stage IN ('Closed Won', 'Closed Lost')
)
SELECT
    contract_tier,
    deal_size_bracket,
    COUNT(*)                                                        AS closed_deals,
    COUNT(*) FILTER (WHERE deal_stage = 'Closed Won')               AS won,
    COUNT(*) FILTER (WHERE deal_stage = 'Closed Lost')              AS lost,
    ROUND(100.0 * COUNT(*) FILTER (WHERE deal_stage = 'Closed Won')
          / COUNT(*), 1)                                            AS win_rate_pct,
    ROUND(AVG(arr_value) FILTER (WHERE deal_stage = 'Closed Won'), 0) AS avg_won_arr,
    -- Elasticity signal: win rate delta vs. the tier's overall win rate
    ROUND(100.0 * COUNT(*) FILTER (WHERE deal_stage = 'Closed Won') / COUNT(*)
        - 100.0 * SUM(COUNT(*) FILTER (WHERE deal_stage = 'Closed Won'))
                  OVER (PARTITION BY contract_tier)
          / SUM(COUNT(*)) OVER (PARTITION BY contract_tier), 1)     AS win_rate_vs_tier_avg_pp
FROM closed
GROUP BY contract_tier, deal_size_bracket
ORDER BY contract_tier, deal_size_bracket;


-- ------------------------------------------------------------
-- QUERY D: ICP Score Validation
-- Does the AI's ICP score actually predict revenue? Win rate by
-- score band, aligned to the routing thresholds (75 = BDR
-- priority, 50 = nurture), with lift vs. the overall win rate.
-- ------------------------------------------------------------
WITH closed AS (
    SELECT
        a.icp_score,
        d.deal_stage
    FROM commercial_deals d
    JOIN accounts_and_leads a ON a.lead_id = d.account_id
    WHERE d.deal_stage IN ('Closed Won', 'Closed Lost')
)
SELECT
    CASE
        WHEN icp_score < 50 THEN '1. <50 (disqualify)'
        WHEN icp_score < 75 THEN '2. 50-74 (nurture)'
        ELSE                     '3. 75+ (BDR priority)'
    END AS icp_band,
    COUNT(*)                                                        AS closed_deals,
    COUNT(*) FILTER (WHERE deal_stage = 'Closed Won')               AS won,
    ROUND(100.0 * COUNT(*) FILTER (WHERE deal_stage = 'Closed Won')
          / COUNT(*), 1)                                            AS win_rate_pct,
    ROUND((1.0 * COUNT(*) FILTER (WHERE deal_stage = 'Closed Won') / COUNT(*))
        / (SELECT 1.0 * COUNT(*) FILTER (WHERE deal_stage = 'Closed Won')
                 / COUNT(*) FROM closed), 2)                        AS lift_vs_overall
FROM closed
GROUP BY 1
ORDER BY 1;
