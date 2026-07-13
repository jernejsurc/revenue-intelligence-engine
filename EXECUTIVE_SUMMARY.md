# Executive Summary — Autonomous B2B Revenue Acceleration Engine

**Jernej Surc · jaysurc@gmail.com**

## The 30-second pitch

"I built a revenue engine that does what a RevOps team of three does manually. When a lead comes into HubSpot, an AI scores it against our ideal customer profile and writes a personalized outreach hook in under a minute — before a BDR ever sees it. Every deal lands in a SQL warehouse where three production queries rank which existing customers are ready to upgrade, how fast deals move by segment, and where our pricing tiers win or lose. It all surfaces in a Power BI dashboard, and the whole stack runs on €0/month of free-tier tools."

## The problem it solves

Revenue teams lose money in three predictable places: BDRs waste hours on leads that will never buy, account managers miss upsell windows because expansion signals live in scattered tools, and leadership prices deals on gut feel because win-rate data by tier is nobody's job. This project automates all three.

## How it works

A Make.com scenario watches HubSpot for new leads and sends each one to the Claude API, which returns an ICP fit score (0–100) and a two-sentence personalized outreach hook. Leads route automatically: high-fit to BDR priority, mid-fit to nurture, low-fit disqualified. Every lead and deal is logged to a serverless PostgreSQL warehouse (Neon), where SQL analytics compute pipeline velocity by company size, a ranked expansion-readiness queue for account managers, and win-rate elasticity across pricing tiers. Power BI sits on top with weighted-pipeline, sales-cycle, and expansion-index measures.

## What it demonstrates

| Capability | Evidence in the project |
|---|---|
| RevOps architecture | 5-tool integrated stack, designed within free-tier constraints |
| Workflow automation | Make.com scenario with API-level HubSpot v3 + Claude integration |
| Production SQL | CTEs, window functions, filtered aggregates on PostgreSQL |
| AI applied to GTM | Prompt-engineered ICP scoring with enforced JSON output |
| BI & data modeling | DAX measures: weighted pipeline ARR, expansion index, ICP conversion |
| Commercial judgment | Metrics chosen to answer real pricing, BDR, and KAM decisions |

## The scenario behind the data

The dataset models **Adriatic Analytics**, a fictional Ljubljana-based B2B SaaS vendor selling pipeline analytics to mid-market tech companies on a four-tier pricing ladder (€6K–€480K ACV). It covers 18 months of GTM history — January 2025 through the FY26 Q2 close (snapshot: 1 July 2026): 150 accounts, 248 deals. The data is calibrated to real B2B SaaS benchmarks — 82–101 day sales cycles that lengthen with company size, 50–66% late-stage win rates, and two-thirds of closes landing in the final week of a fiscal quarter — so every query output reads like an actual pipeline review, and it's deterministic, so the numbers reproduce exactly in a live walkthrough.

## Results (on the seeded dataset)

Lead scoring latency drops from a manual review cycle to under 60 seconds per lead. The expansion query surfaces 22 upgrade-ready accounts (health score >80 on lower tiers) ranked by weighted ARR upside. Win-rate elasticity analysis shows conversion by tier × deal size — the exact table a pricing review starts from. Operating cost: €0/month.

## One line per audience

For a **RevOps role**: "I architected the full lead-to-dashboard data flow across five integrated tools." For a **GTM/BDR role**: "The engine hands reps pre-scored leads with a ready-to-send personalized opener." For a **KAM role**: "It produces a ranked Monday-morning upsell queue from live account health signals." For a **pricing/revenue analyst role**: "The elasticity query shows exactly where each tier wins, loses, and leaves money on the table."
