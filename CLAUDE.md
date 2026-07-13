# Autonomous B2B Revenue Acceleration Engine

Portfolio project by Jernej Surc. A 100% free-tier commercial intelligence system that automates lead enrichment, calculates expansion scores, stores transaction logs, and visualizes pipeline velocity.

## Tech Stack (all free tier)

| Layer | Tool | Notes |
|---|---|---|
| CRM | HubSpot CRM Free (API v3) | Lead/deal source of truth |
| Automation | Make.com (1,000 ops/mo) | HubSpot → Claude → Sheets → Neon |
| AI Scoring | Claude API | ICP score (0–100) + BDR outreach hook |
| Database | Neon PostgreSQL (serverless) | SSL required; psycopg v3 |
| Staging | Google Sheets | Lookup rules, enrichment staging |
| Analytics | Power BI Desktop | DAX measures in `powerbi_measures.dax` |

## Project Files

- `CLAUDE.md` - this file (project guidelines)
- `schema.sql` - DDL for `accounts_and_leads` and `commercial_deals` (Neon PostgreSQL)
- `seed_data.py` - psycopg v3 seed script; injects 150 realistic B2B SaaS accounts + deals
- `analytics_queries.sql` - Phase 2: pipeline velocity, KAM expansion readiness, win-rate/tier elasticity
- `make_payload_template.json` - Phase 3: JSON payloads between HubSpot, Make, Sheets, Neon
- `make_scenario_blueprint.json` - Phase 3: importable Make.com scenario (Import Blueprint in Make UI; do not run/edit locally). Deployed live as scenario 6507604 (team 1110634, eu1.make.com), smoke-tested end-to-end 2026-07-10, currently deactivated pending HubSpot contact-cap headroom.
- `powerbi_measures.dax` - Phase 4: Weighted Pipeline ARR, Avg Days to Close, Expansion Readiness Index, ICP Conversion %, Snapshot Date + Avg Days in Pipeline (Open) anchored to the 2026-07-01 snapshot
- `.env.example` - copy to `.env`, set `DATABASE_URL`
- `BUILD_STORY.md` - build log / debugging narrative from the live Make.com deployment (portfolio storytelling asset)

## Setup & Run

```bash
# 1. Install dependencies
pip install "psycopg[binary]" python-dotenv

# 2. Configure Neon connection (SSL enforced)
cp .env.example .env
# Edit .env: DATABASE_URL=postgresql://USER:PASSWORD@HOST/neondb?sslmode=require

# 3. Apply schema (Neon SQL Editor, or psql)
psql "$DATABASE_URL" -f schema.sql

# 4. Seed mock data (idempotent - truncates then reloads)
python seed_data.py
```

## Conventions

- Python: psycopg v3 only (never psycopg2), parameterized queries, type hints, `python-dotenv` for secrets. Never hardcode credentials.
- SQL: PostgreSQL 16 syntax, lowercase snake_case identifiers, explicit constraints and indexes.
- Mock data: deterministic (`random.seed(42)`) and anchored to a fixed reporting snapshot (1 July 2026 = FY26 Q2 close; history from January 2025) so analytics results are reproducible in interviews. Closed deals cluster at fiscal quarter ends by design. Query A measures open-deal age against the same snapshot, not `now()`.
- Deal stages: Discovery → Qualification → Proposal → Negotiation → Closed Won / Closed Lost.
- Contract tiers: Starter, Growth, Scale, Enterprise.

## Verify

```bash
python -m py_compile seed_data.py          # syntax check
psql "$DATABASE_URL" -c "SELECT count(*) FROM accounts_and_leads;"   # expect 150
```

## Claude Code Session Guidelines

All files in this repo were scaffolded and syntax-verified. Claude Code's job is **live execution and iteration**, not regeneration:

1. Never overwrite `.env`; never print or commit the `DATABASE_URL` value.
2. Before any DB work, confirm connectivity: `psql "$DATABASE_URL" -c "SELECT version();"`.
3. Apply `schema.sql` before running `seed_data.py`. The seed script truncates - safe to re-run.
4. After seeding, validate: 150 rows in `accounts_and_leads`, 200–300 in `commercial_deals`, and all three queries in `analytics_queries.sql` return non-empty results.
5. When editing queries, keep them compatible with Power BI import mode (no session-scoped temp tables).
6. Suggested first prompt: "Read CLAUDE.md, verify the DB connection, apply schema.sql, run seed_data.py, then run all three analytics queries and show me the results."
