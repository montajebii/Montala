#!/usr/bin/env python3
"""Sync the bundled seed datasets (assets/data/) from the engine repo.

The price datasets live in the standalone tgju-asset-history repository;
this app bundles a snapshot of them for offline first-run. Sources:

  --remote URL   download data/<name>.csv from a URL base (default: the
                 engine repo's raw main branch — what CI uses)
  --local DIR    copy from a local checkout of the engine repo
                 (default when neither flag is given: ../tgju-asset-history/data)

Every downloaded/copied file is sanity-checked (header + minimum rows)
before replacing the bundled copy, so a truncated download cannot poison
the app.

Usage:
    python3 tools/sync_app_assets.py              # local engine checkout
    python3 tools/sync_app_assets.py --remote https://raw.githubusercontent.com/montajebii/tgju-asset-history/main/data
    python3 tools/sync_app_assets.py --check      # verify only, exit 1 on drift
"""

import argparse
import csv
import glob
import os
import shutil
import sys
import urllib.request

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSET_DIR = os.path.join(REPO_ROOT, "assets", "data")
DEFAULT_LOCAL = os.path.join(os.path.dirname(REPO_ROOT), "tgju-asset-history", "data")
DEFAULT_REMOTE = (
    "https://raw.githubusercontent.com/montajebii/tgju-asset-history/main/data"
)

DATASETS = [
    "dollar_price_history.csv",
    "gold_price_history.csv",
    "geram24_price_history.csv",
    "sekee_price_history.csv",
    "sekeb_price_history.csv",
    "nim_price_history.csv",
    "rob_price_history.csv",
    "gerami_price_history.csv",
]

EXPECTED_HEADER = ["Date", "Persian_Date", "Open", "Low", "High", "Close"]
MIN_ROWS = 3000


def sanity_check(path):
    """Raise ValueError when the file does not look like our dataset."""
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        if header != EXPECTED_HEADER:
            raise ValueError(f"bad header: {header!r}")
        rows = sum(1 for _ in reader)
    if rows < MIN_ROWS:
        raise ValueError(f"only {rows} rows (< {MIN_ROWS}) — looks truncated")
    return rows


def fetch(src, dst_tmp):
    if src.startswith("http://") or src.startswith("https://"):
        request = urllib.request.Request(src, headers={"User-Agent": "montala-sync"})
        with urllib.request.urlopen(request, timeout=60) as r, open(dst_tmp, "wb") as f:
            f.write(r.read())
    else:
        shutil.copy2(src, dst_tmp)


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--remote", help="URL base to download datasets from")
    parser.add_argument("--local", help="local engine data/ directory")
    parser.add_argument("--check", action="store_true", help="verify only")
    args = parser.parse_args(argv)

    source = args.remote or (args.local or DEFAULT_LOCAL)
    mode = "remote" if (args.remote or (not args.local and source == DEFAULT_REMOTE and not os.path.isdir(DEFAULT_LOCAL))) else "local"
    if args.remote:
        mode = "remote"
    elif args.local:
        mode = "local"
    elif os.path.isdir(DEFAULT_LOCAL):
        mode = "local"
    else:
        mode = "remote"

    os.makedirs(ASSET_DIR, exist_ok=True)
    drifted = []
    for name in DATASETS:
        src = f"{source.rstrip('/')}/{name}"
        dst = os.path.join(ASSET_DIR, name)
        tmp = dst + ".tmp"
        try:
            fetch(src, tmp)
            rows = sanity_check(tmp)
        except Exception as exc:
            if os.path.exists(tmp):
                os.remove(tmp)
            print(f"  FAIL {name}: {exc}")
            return 1
        same = os.path.exists(dst) and open(dst, "rb").read() == open(tmp, "rb").read()
        if args.check:
            print(f"  {'ok' if same else 'drifted'} {name} ({rows} rows)")
            if not same:
                drifted.append(name)
            os.remove(tmp)
            continue
        if same:
            print(f"  ok      {name}")
            os.remove(tmp)
        else:
            os.replace(tmp, dst)
            print(f"  synced  {name} ({rows} rows)")

    if args.check and drifted:
        print(f"\n{len(drifted)} dataset(s) drifted from the engine repo")
        return 1
    print(f"\nbundled datasets are in sync ({mode} source)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
