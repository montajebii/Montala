# Test fixtures

Real payloads captured on 2026-11-20 for the live-board regression tests.

| File | Source | Shape |
|---|---|---|
| `tgju_live_widget.json` | `https://api.tgju.org/v1/widget/tmp?keys=sekee,sekeb,geram24,geram18,mesghal,nim,rob,gerami,ons,gold_futures,silver,silver_999,gc16` | Verbatim response, all 13 indicators. Map rows by `response.indicators[].name`. |
| `tgju_summary_ons.json` | `https://api.tgju.org/v1/market/indicator/summary-table-data/ons?lang=fa&order_dir=asc` | Verbatim response envelope, `data` trimmed to the last three rows. Row layout: `[open, low, high, close, change, changePct, gregorian, jalali]`. |
| `tgju_summary_silver.json` | same, slug `silver` | same |
| `tgju_summary_silver_999.json` | same, slug `silver_999` | same |
| `estjt_tv.html` | `https://www.estjt.ir/tv/` | Verbatim HTML board. |
| `legacy_transactions.csv` | m0ntIsRich `transactions.csv` (project source) | Verbatim Python CSV, 7 columns, `shemsh24` alias. |
| `legacy_sarmaye_history.csv` | m0ntIsRich `sarmaye_history.csv` | Header plus the last three rows of the Python value-history matrix. |

The `_fixture` object added to the summary files documents capture time, the
public page and the API URL. The `data` rows themselves are unmodified; only
older history was dropped to keep the repository small.

Public pages for the captured symbols:

- <https://www.tgju.org/profile/ons>
- <https://www.tgju.org/profile/silver>
- <https://www.tgju.org/profile/silver_999>

See `docs/live-board-pricing.md` for the arithmetic these fixtures pin down.
