#!/usr/bin/env python3
"""Convert m0ntIsRich data files into Montala's portfolio import CSV.

Inputs (read-only, never modified):
  * transactions.csv    — explicit BUY/SELL log: maps 1:1 onto Montala's
                          `date,asset,type,units,unit_price_toman,note` with
                          the asset-name translation (shemsh24→gold24,
                          shemsh18→gold18, sekee→sekee).
  * sarmaye_history.csv — per-run portfolio snapshots. Montala derives history
                          from transactions, so snapshots are converted back
                          into the BUY/SELL events they imply: a change in a
                          unit column between consecutive snapshots becomes a
                          trade on that date, priced at the snapshot's own
                          per-unit value (exactly what main.py's trend
                          analysis did).

Outputs land in montala's dist/ (gitignored):
  montala_import_transactions.csv  — from transactions.csv
  montala_import_history.csv       — derived from sarmaye_history.csv

Import both into the «ارزش دارایی من» tool with merge; the tool sorts and
merges everything by date.
"""

import csv
import os
import sys

SRC_DIR = "/home/mompateji/GitM0nt/m0ntIsRich"
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "dist")

ASSET_MAP = {
    "sekee": "sekee",
    "shemsh24": "gold24",
    "shemsh18": "gold18",
}

# Snapshot columns per asset: (units_col, value_col)
SNAPSHOT_ASSETS = [
    ("sekee", "sekee_units", "sekee_value_toman"),
    ("gold24", "shemsh24_units", "shemsh24_value_toman"),
    ("gold18", "shemsh18_units", "shemsh18_value_toman"),
]

OUT_HEADER = ["date", "asset", "type", "units", "unit_price_toman", "note"]


def iso_date(ts: str) -> str:
    """'2026-09-03 03:41:00' (or with microseconds) → '2026-09-03'."""
    return ts.strip().split(" ")[0]


def convert_transactions(path: str) -> list[dict]:
    out = []
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            asset = ASSET_MAP.get(row["asset"].strip())
            if asset is None:
                print(f"  ! skip unknown asset {row['asset']!r}")
                continue
            out.append({
                "date": iso_date(row["timestamp"]),
                "asset": asset,
                "type": row["event_type"].strip().upper(),
                "units": row["units"].strip(),
                "unit_price_toman": row["unit_price_toman"].strip(),
                "note": row.get("source", "").strip(),
            })
    return out


def convert_snapshots(path: str) -> list[dict]:
    """Derive trades from unit diffs between consecutive snapshots."""
    with open(path, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        return []

    out = []
    prev = {key: 0.0 for key, _, _ in SNAPSHOT_ASSETS}

    for i, row in enumerate(rows):
        date = iso_date(row["timestamp"])
        for key, units_col, value_col in SNAPSHOT_ASSETS:
            try:
                units = float(row[units_col] or 0)
                value = float(row[value_col] or 0)
            except ValueError:
                continue
            diff = round(units - prev[key], 6)
            if abs(diff) < 0.001:
                continue  # unchanged since the last snapshot
            unit_price = value / units if units > 0 else 0
            if unit_price <= 0:
                print(f"  ! skip {key} @ {date}: zero unit price")
                continue
            note = "از تاریخچه سارمیه"
            if i == 0:
                note = "موجودی اولیه (از تاریخچه سارمیه)"
            out.append({
                "date": date,
                "asset": key,
                "type": "BUY" if diff > 0 else "SELL",
                "units": f"{abs(diff):.6f}".rstrip("0").rstrip("."),
                "unit_price_toman": f"{unit_price:.0f}",
                "note": note,
            })
            prev[key] = units

    return out


def write(path: str, rows: list[dict]) -> None:
    rows.sort(key=lambda r: r["date"])
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=OUT_HEADER)
        writer.writeheader()
        writer.writerows(rows)
    print(f"  -> {path}  ({len(rows)} trades)")


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    tx_path = os.path.join(SRC_DIR, "transactions.csv")
    hist_path = os.path.join(SRC_DIR, "sarmaye_history.csv")
    for p in (tx_path, hist_path):
        if not os.path.exists(p):
            print(f"missing input: {p}", file=sys.stderr)
            return 1

    print("converting transactions.csv:")
    txs = convert_transactions(tx_path)
    write(os.path.join(OUT_DIR, "montala_import_transactions.csv"), txs)

    print("converting sarmaye_history.csv (snapshots → implied trades):")
    hist = convert_snapshots(hist_path)
    write(os.path.join(OUT_DIR, "montala_import_history.csv"), hist)

    print(
        "\nimport both files from «ارزش دارایی من» → تب تراکنش‌ها → "
        "دکمه ورودی CSV → choose merge for each."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
