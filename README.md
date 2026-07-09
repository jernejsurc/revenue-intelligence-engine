# Autonomous B2B Revenue Acceleration Engine

An end-to-end commercial intelligence system built entirely on free tiers. Inbound leads are AI-scored and enriched in under a minute, routed by ICP fit, logged to a serverless SQL warehouse, and visualized in a live Power BI revenue dashboard.

**Built by Jernej Surc** — RevOps / GTM / Revenue Analytics. Demonstrates CRM architecture, workflow automation, production SQL, AI prompt engineering, and BI modeling in one working system.

## Business scenario

The dataset models **Adriatic Analytics**, a fictional Ljubljana-based B2B SaaS vendor selling a pipeline-analytics platform to mid-market tech companies across ten verticals (FinTech, HealthTech, Cybersecurity, DevTools, and others). Pricing runs four tiers, from Starter ($6–18K ACV) to Enterprise ($150–480K ACV). The company moved its GTM tracking off spreadsheets and into HubSpot in **January 2025**; the warehouse holds every account and deal from then through the **FY26 Q2 close** (reporting snapshot: 1 July 2026) — 150 accounts and 248 deals over 18 months.

The mock data is calibrated to published B2B SaaS benchmarks so the analytics read like a genuine pipeline review:

- **Sales cycles average 82–101 days**, lengthening with company size — in line with the 2–3 month norm for mid-market ACV deals.
- **Late-stage win rates land in the 50–66% band** across tiers, and correlate with the AI's ICP score by construction.
- **Two-thirds of closes cluster in the final week of a fiscal quarter** — the classic rep-incentive pile-up every RevOps team will recognize.
- **~30% of Starter/Growth customers show high expansion intent** (health score >80) within their first year, feeding the KAM upsell queue.

Everything is deterministic (`seed=42`) and anchored to the fixed snapshot date, so every reseed reproduces the exact numbers quoted here.

## Architecture

```
HubSpot CRM (API v3)          Claude API                Google Sheets
  new lead webhook   ──►  ICP score (0-100) +   ──►   staging + routing
                          2-sentence BDR hook          rules (BDR/nurture)
                                                              │
Power BI Desktop     ◄──  Neon PostgreSQL        ◄────────────┘
  velocity, win-rate,     accounts_and_leads,          Make.com orchestrates
  expansion dashboards    commercial_deals             every hop (~6 ops/lead)
```

Total cost: **$0/month** (HubSpot Free, Make.com 1,000 ops, Neon free serverless, Google Sheets, Power BI Desktop).

## What it does

Automates lead enrichment with AI (Claude assigns every inbound lead an ICP score and writes a personalized outreach hook, written back to HubSpot so BDRs never touch unscored leads). Ranks expansion opportunities (SQL identifies Closed Won accounts on lower tiers with health scores >80 and ranks them by weighted ARR upside — a Monday-morning upsell queue for KAMs). Measures what matters (pipeline velocity by segment, win-rate elasticity by tier and deal size, weighted pipeline ARR, and whether the AI's ICP scores actually predict revenue).

## Repository

| File | Purpose |
|---|---|
| `schema.sql` | PostgreSQL DDL — 2 tables, constraints, analytics indexes |
| `seed_data.py` | psycopg v3 seed script — 150 accounts + 248 deals, Jan 2025 → Jul 2026, quarter-end close clustering |
| `analytics_queries.sql` | Query A: pipeline velocity · Query B: KAM expansion readiness · Query C: win-rate & tier elasticity |
| `make_payload_template.json` | Exact JSON contract at every Make.com hop |
| `make_scenario_blueprint.json` | Importable Make.com scenario blueprint (validated against Make's schema) |
| `powerbi_measures.dax` | Weighted Pipeline ARR, Avg Days to Close, Expansion Readiness Index, ICP Conversion % |
| `EXECUTIVE_SUMMARY.md` | One-page project brief for recruiters & hiring managers |
| `CLAUDE.md` | Project guidelines for Claude Code |

## Quick start

```bash
pip install -r requirements.txt
cp .env.example .env               # add your Neon DATABASE_URL (sslmode=require)
psql "$DATABASE_URL" -f schema.sql
python seed_data.py                # 150 accounts, ~250 deals, seed=42
psql "$DATABASE_URL" -f analytics_queries.sql
```

## Make.com scenario setup (6 modules, free tier)

**Fast path:** in Make, create a new scenario → ⋯ menu → *Import Blueprint* → upload `make_scenario_blueprint.json`, then link your HubSpot, Anthropic, Google Sheets, and PostgreSQL (Neon) connections. The flow:

1. **HubSpot > Watch CRM Objects** (`hubspotcrm:WatchCRMObjects`) — trigger on new contact (API v3).
2. **Anthropic Claude > Create a Prompt** (`anthropic-claude:createAMessage`) — system prompt forces JSON output: `{"icp_score": <0-100>, "bdr_snippet": "<2 sentences>"}` (see `make_payload_template.json`).
3. **JSON > Parse JSON** — validate Claude's response.
4. **Google Sheets > Add a Row** (`google-sheets:addRow`) — staging log; routing computed inline: ICP ≥ 75 → BDR_PRIORITY, 50–74 → NURTURE, else DISQUALIFY (swap in a Router module if you prefer visual branching).
5. **PostgreSQL > Execute a Query** (`postgres:Query`) — insert into Neon `accounts_and_leads` (SSL).
6. **HubSpot > Update a Record** (`hubspotcrm:UpdateRecord`) — write score, hook, and routing back to the lead.

Budget: ~6 ops/lead → ~150 leads/month inside the 1,000-op free tier.

## Power BI dashboard (3 pages)

1. **Pipeline Command Center** — Weighted Pipeline ARR card, funnel by stage, velocity by company size (Query A).
2. **KAM Expansion Radar** — Expansion Readiness Index gauge, ranked upsell table (Query B).
3. **Pricing & Win-Rate Elasticity** — win-rate matrix by tier × deal size (Query C), ICP Conversion % trend.
