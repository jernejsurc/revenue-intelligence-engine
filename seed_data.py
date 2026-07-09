"""
seed_data.py — Autonomous B2B Revenue Acceleration Engine
Populates Neon PostgreSQL (over SSL) with 150 realistic B2B SaaS accounts
and their commercial deals using psycopg v3.

Usage:
    pip install "psycopg[binary]" python-dotenv
    cp .env.example .env   # set DATABASE_URL (must include sslmode=require)
    python seed_data.py

Idempotent: truncates both tables, then reloads. Deterministic (seed=42)
so downstream analytics results are reproducible.
"""

from __future__ import annotations

import os
import random
import sys
from datetime import date, datetime, timedelta, timezone

import psycopg
from dotenv import load_dotenv

random.seed(42)

N_ACCOUNTS = 150

# ---------------------------------------------------------------- mock config
INDUSTRIES = [
    "FinTech", "HealthTech", "Cybersecurity", "MarTech", "DevTools",
    "LogisticsTech", "HRTech", "LegalTech", "EdTech", "PropTech",
]

NAME_PREFIX = [
    "Nova", "Vertex", "Blue", "Quantum", "Signal", "Atlas", "Ember",
    "North", "Pulse", "Cirrus", "Forge", "Lumen", "Delta", "Orbit", "Vector",
]
NAME_SUFFIX = [
    "Metrics", "Ledger", "Stack", "Flow", "Works", "Labs", "Grid",
    "Base", "Loop", "Path", "Layer", "Sync", "Scale", "Ops", "IQ",
]

STAGES_OPEN = ["Discovery", "Qualification", "Proposal", "Negotiation"]
STAGE_WIN_PROB = {
    "Discovery": (0.05, 0.20),
    "Qualification": (0.20, 0.40),
    "Proposal": (0.40, 0.65),
    "Negotiation": (0.60, 0.85),
}

# tier -> (ARR range, employee-count weighting)
TIERS = {
    "Starter":    (6_000, 18_000),
    "Growth":     (18_000, 60_000),
    "Scale":      (60_000, 150_000),
    "Enterprise": (150_000, 480_000),
}

SNIPPET_TEMPLATES = [
    ("Noticed {company} is scaling its {industry} platform past {emp} employees — teams at that "
     "stage usually hit a wall with manual pipeline reporting. We help RevOps automate deal-stage "
     "analytics so forecasts stop living in spreadsheets."),
    ("Saw {company} hiring across GTM roles, which usually means outbound volume is about to "
     "outgrow your lead-routing rules. Our engine scores and routes inbound leads in under a "
     "minute so your BDRs only touch high-ICP accounts."),
    ("{company}'s growth in {industry} suggests your account teams are juggling expansion signals "
     "manually. We surface upgrade-ready accounts automatically so KAMs act on usage spikes the "
     "same week they happen."),
    ("With {emp}+ people, {company} likely has renewal data scattered across CRM and billing. We "
     "unify contract tiers and usage into one expansion score, giving your team a ranked "
     "upsell queue every Monday."),
]


def rand_dt_between(start: datetime, end: datetime) -> datetime:
    return start + timedelta(seconds=random.randint(0, int((end - start).total_seconds())))


def make_accounts(now: datetime) -> list[tuple]:
    """150 accounts created over the trailing 18 months."""
    used_names: set[str] = set()
    rows = []
    window_start = now - timedelta(days=548)
    for _ in range(N_ACCOUNTS):
        while True:
            name = f"{random.choice(NAME_PREFIX)}{random.choice(NAME_SUFFIX)}"
            if name not in used_names:
                used_names.add(name)
                break
        industry = random.choice(INDUSTRIES)
        employee_count = random.choice(
            [random.randint(11, 50), random.randint(51, 200),
             random.randint(201, 1000), random.randint(1001, 5000)]
        )
        # ICP skews higher for mid-market+ (realistic fit curve)
        base = 35 if employee_count < 51 else 50 if employee_count < 201 else 60
        icp_score = round(min(100, random.gauss(base + 15, 14)), 2)
        icp_score = max(0, icp_score)
        snippet = random.choice(SNIPPET_TEMPLATES).format(
            company=name, industry=industry, emp=employee_count
        )
        created_at = rand_dt_between(window_start, now - timedelta(days=14))
        rows.append((name, industry, employee_count, icp_score, snippet, created_at))
    return rows


def pick_tier(employee_count: int) -> str:
    if employee_count <= 50:
        return random.choices(["Starter", "Growth"], weights=[70, 30])[0]
    if employee_count <= 200:
        return random.choices(["Starter", "Growth", "Scale"], weights=[25, 55, 20])[0]
    if employee_count <= 1000:
        return random.choices(["Growth", "Scale", "Enterprise"], weights=[30, 50, 20])[0]
    return random.choices(["Scale", "Enterprise"], weights=[40, 60])[0]


def make_deals(accounts: list[tuple], ids: list[int], now: datetime) -> list[tuple]:
    """~1-3 deals per account: new business + expansion motions with
    high-intent expansion signals on a realistic subset."""
    deals = []
    for lead_id, acct in zip(ids, accounts):
        _, _, employee_count, icp_score, _, created_at = acct
        for _ in range(random.choices([1, 2, 3], weights=[45, 40, 15])[0]):
            tier = pick_tier(employee_count)
            lo, hi = TIERS[tier]
            arr = round(random.uniform(lo, hi), 2)
            opened = rand_dt_between(created_at, now - timedelta(days=7))
            age_days = (now - opened).days

            closed = random.random() < min(0.85, 0.25 + age_days / 200)
            if closed:
                # win rate correlates with ICP score
                won = random.random() < (0.25 + icp_score / 200)
                stage = "Closed Won" if won else "Closed Lost"
                win_prob = 1.0 if won else 0.0
                cycle = random.randint(21, 120) if tier in ("Starter", "Growth") \
                    else random.randint(45, 180)
                close_date = min((opened + timedelta(days=cycle)).date(),
                                 now.date() - timedelta(days=1))
            else:
                stage = random.choice(STAGES_OPEN)
                win_prob = round(random.uniform(*STAGE_WIN_PROB[stage]), 3)
                close_date = None

            # ~30% of won Starter/Growth accounts show high-intent expansion signals
            if stage == "Closed Won" and tier in ("Starter", "Growth") and random.random() < 0.30:
                expansion = round(random.uniform(80, 99), 2)
            else:
                expansion = round(max(0, min(100, random.gauss(52, 20))), 2)

            deals.append((lead_id, stage, tier, arr, win_prob, expansion,
                          close_date, opened))
    return deals


def main() -> None:
    load_dotenv()
    dsn = os.getenv("DATABASE_URL")
    if not dsn:
        sys.exit("ERROR: DATABASE_URL not set. Copy .env.example to .env and configure it.")
    if "sslmode" not in dsn:
        dsn += ("&" if "?" in dsn else "?") + "sslmode=require"  # Neon requires SSL

    now = datetime.now(timezone.utc)
    accounts = make_accounts(now)

    with psycopg.connect(dsn) as conn:
        with conn.cursor() as cur:
            cur.execute("TRUNCATE commercial_deals, accounts_and_leads RESTART IDENTITY CASCADE;")

            cur.executemany(
                """
                INSERT INTO accounts_and_leads
                    (company_name, industry, employee_count, icp_score,
                     bdr_ai_snippet, created_at)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                accounts,
            )
            cur.execute("SELECT lead_id FROM accounts_and_leads ORDER BY lead_id;")
            ids = [r[0] for r in cur.fetchall()]

            deals = make_deals(accounts, ids, now)
            cur.executemany(
                """
                INSERT INTO commercial_deals
                    (account_id, deal_stage, contract_tier, arr_value,
                     win_probability, expansion_signal_score, close_date, created_at)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                """,
                deals,
            )
        conn.commit()

    print(f"Seeded {len(accounts)} accounts and {len(deals)} deals into Neon PostgreSQL.")


if __name__ == "__main__":
    main()
