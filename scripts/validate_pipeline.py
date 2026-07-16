"""
validate_pipeline.py - CI guardrail for the Revenue Intelligence Engine.

Applies schema.sql, reseeds via seed_data.py, then asserts the known
fingerprints of the deterministic dataset (seed=42, snapshot 2026-07-01).
Any drift in schema, seed logic, or analytics queries fails the build.

Usage: DATABASE_URL=postgresql://... python scripts/validate_pipeline.py
"""

from __future__ import annotations

import os
import subprocess
import sys
from decimal import Decimal
from pathlib import Path

import psycopg

ROOT = Path(__file__).resolve().parent.parent
FAILURES: list[str] = []


def check(label: str, actual, expected) -> None:
    ok = actual == expected
    print(f"{'PASS' if ok else 'FAIL'}  {label}: {actual!r}"
          + ("" if ok else f" (expected {expected!r})"))
    if not ok:
        FAILURES.append(label)


def split_statements(sql: str) -> list[str]:
    """Split on top-level semicolons (no dollar-quoting in these files)."""
    stmts, buf = [], []
    for line in sql.splitlines():
        stripped = line.strip()
        if stripped.startswith("--") and not buf:
            continue
        buf.append(line)
        if stripped.endswith(";"):
            stmt = "\n".join(buf).strip()
            if stmt and stmt != ";":
                stmts.append(stmt)
            buf = []
    return stmts


def main() -> None:
    dsn = os.environ.get("DATABASE_URL")
    if not dsn:
        sys.exit("ERROR: DATABASE_URL not set")

    print("== Applying schema ==")
    with psycopg.connect(dsn) as conn:
        conn.execute((ROOT / "schema.sql").read_text(encoding="utf-8"))
        conn.commit()

    print("== Seeding (deterministic, seed=42) ==")
    subprocess.run([sys.executable, str(ROOT / "seed_data.py")],
                   check=True, cwd=ROOT)

    queries = split_statements(
        (ROOT / "analytics_queries.sql").read_text(encoding="utf-8"))
    assert len(queries) == 4, f"expected 4 analytics queries, found {len(queries)}"

    print("== Asserting dataset fingerprints ==")
    with psycopg.connect(dsn) as conn, conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM accounts_and_leads;")
        check("accounts", cur.fetchone()[0], 150)

        cur.execute("""SELECT count(*), sum(arr_value),
                              count(*) FILTER (WHERE close_date IS NULL)
                       FROM commercial_deals;""")
        deals, arr, open_deals = cur.fetchone()
        check("deals", deals, 248)
        check("total ARR", arr, Decimal("27688910.33"))
        check("open deals", open_deals, 74)

        cur.execute(queries[0])
        check("Query A rows (velocity)", len(cur.fetchall()), 16)

        cur.execute(queries[1])
        rows = cur.fetchall()
        check("Query B rows (expansion)", len(rows), 22)
        check("Query B top account", rows[0][1], "AtlasLayer")
        check("Query B top weighted value", rows[0][7], Decimal("208116"))

        cur.execute(queries[2])
        rows = cur.fetchall()
        check("Query C rows (elasticity)", len(rows), 6)
        enterprise = next(r for r in rows if r[0] == "Enterprise")
        check("Query C Enterprise win rate", enterprise[5], Decimal("65.6"))

        cur.execute(queries[3])
        rows = cur.fetchall()
        check("Query D bands (ICP validation)", len(rows), 3)
        check("Query D win rates monotonic",
              [r[3] for r in rows],
              [Decimal("32.3"), Decimal("59.5"), Decimal("66.1")])

    if FAILURES:
        sys.exit(f"\n{len(FAILURES)} check(s) failed: {', '.join(FAILURES)}")
    print("\nAll fingerprints verified - dataset and analytics are reproducible.")


if __name__ == "__main__":
    main()
