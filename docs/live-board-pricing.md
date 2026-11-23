# Live-board pricing diagnosis

Captured on 2026-11-20 between 16:49 and 16:56 Asia/Tehran (13:19–13:26 UTC)
against the production endpoints. This document is the Phase 1 output: it
records what the APIs return, what the app does with those bytes, and why the
three reported values were wrong. No code changed in this phase.

## Endpoints

| Purpose | URL | CORS | Notes |
|---|---|---|---|
| Daily archive (what the board used) | `https://api.tgju.org/v1/market/indicator/summary-table-data/{slug}?lang=fa&order_dir=asc` | `access-control-allow-origin: *` | 1.7–2.1 MB per slug for `ons`/`silver`; 291 KB for `silver_999`. One row per trading day; no intraday row. |
| Live quotes (what the tgju pages use) | `https://api.tgju.org/v1/widget/tmp?keys={comma-separated slugs}` | `access-control-allow-origin: *` | 6 KB for all 13 board slugs; one `p` (current price) per indicator. |
| Live quotes (legacy host) | `https://call1.tgju.org/ajax.json` | none | Same live values under `current.{slug}.p`, but no CORS header — unusable on web. Used below only to cross-check numbers. |
| estjt board | `https://www.estjt.ir/tv/` | none | 38 KB HTML, one `div.tt-price-card` per instrument. No rate-limit headers. |

The live widget response is keyed by `response.indicators[].name` (the slug
that was requested), not by `.slug` (tgju's internal Persian slug, e.g.
`سکه-امامی-2`). `.p` is a string that may contain thousands separators.

### Daily archive row layout

`parseApiPayload` in `lib/core/net/updater.dart` documents the layout, and the
captured payloads confirm it:

```
[0] open, [1] low, [2] high, [3] close,
[4] change (HTML span), [5] change percent (HTML span),
[6] Gregorian date, [7] Jalali date
```

The last row of the archive on Friday 2026-11-20 is **2026/11/19** — the
previous trading day. `order_dir=asc` means `data.last` is the most recent
*closed* day, never the live intraday quote.

## Bug 1 — gold ounce (`ons`) shows `۳۶۷ تومان`

Captured archive tail (`test/fixtures/tgju_summary_ons.json`):

```
["3,728.82", "3,662.93", "3,755.60", "3,668.25", …, "2026/11/19", "1405/08/28"]
```

Captured live value (`test/fixtures/tgju_live_widget.json`, name `ons`):
`p = "3569.88"` USD. The public page showed `$3,578.76` at 16:49 and the feed
moved to `$3,569.88` at 16:53.

What the app does (`_fetchTgjuSlug` in `lib/core/net/live_quotes.dart`):

1. Takes `data.last[3]` → `3668.25`.
2. Calls `parseLooseMarketNumber('3668.25')`. The parser sets `isUsd` only when
   the raw text contains `$`. The archive has no `$`, so `isUsd = false`.
3. Falls into the Rial branch: `toman = 3668.25 / 10 = 366.825`.
4. `formatLiveCell` rounds to `۳۶۷` and labels it `تومان`.

Root cause: the row has no currency metadata, so a USD-denominated slug is
treated as Rial and divided by ten. The archive is also the wrong source for a
live board — it ends at the previous close.

## Bug 2 — silver ounce (`silver`) shows `۴ تومان`

Captured archive tail (`test/fixtures/tgju_summary_silver.json`):

```
["45.10", "44.01", "45.84", "44.06", …, "2026/11/19", "1405/08/28"]
```

Captured live value (`test/fixtures/tgju_live_widget.json`, name `silver`):
`p = "41.97"` USD. `call1.tgju.org/ajax.json` reported `41.96` at 16:50.

The pipeline is identical to bug 1: `44.06 / 10 = 4.406` → `۴ تومان`.

Root cause: same missing currency metadata and the same unconditional ÷10 as
the gold ounce; neither `LiveBoardRow` nor `LiveCell` records that these two
slugs are USD.

## Bug 3 — silver 999 (`silver_999`) shows `۴۱۶٬۶۳۰ تومان`

Captured archive tail (`test/fixtures/tgju_summary_silver_999.json`):

```
["4,150,600", "4,114,700", "4,272,800", "4,166,300", …, "2026/11/19", "1405/08/28"]
```

Captured live value (`test/fixtures/tgju_live_widget.json`, name `silver_999`):
`p = "4051800"` Rial. `ajax.json` reported `4,051,800` at 16:50.

What the app does:

1. `data.last[3]` → `4166300` Rial (2026-11-19 close).
2. `4166300 / 10 = 416630` Toman.
3. Displays `۴۱۶٬۶۳۰ تومان` (or `۴٬۱۶۶٬۳۰۰ ریال` when the Rial setting is on).

The Rial→Toman division is correct here — `4166300 / 10 = 416630`. The number
is wrong because it is yesterday's close, not today's live quote. The live
value at capture time was `4,051,800` Rial (`405,180` Toman), a 2.8% gap. The
reported "4,091,000 Rial" was the page's live value earlier in the day.

Root cause: the board reads the daily archive instead of the live quote feed,
so every IRR instrument lags by one trading day (and diverges intraday). This
is a source/freshness bug, not a second conversion bug: the code has no
double ÷10. The only hardcoded conversion is the single `/ 10` in
`_fetchTgjuSlug`, and `formatLiveCell`'s `× 10` only exists to *display* the
stored Toman value as Rial.

## Bug 4 — intermittent estjt failures

Measurements from this network (each request is a full `https://www.estjt.ir/tv/`
download):

| Test | Requests | Result |
|---|---|---|
| Single request | 1 | HTTP 200, 38,118 bytes, 8.91 s |
| 5 concurrent | 5 | 5× HTTP 200, 4.9–6.4 s |
| 3 sequential | 3 | 3× HTTP 200, 4.8–6.1 s |
| 10 concurrent burst | 10 | 10× HTTP 200, 4.2–5.5 s |

Observed headers: `HTTP/2 200`, `content-type: text/html; charset=UTF-8`,
`x-powered-by: PHP/8.2.35`, **no** `access-control-allow-origin`, **no**
`retry-after`, **no** rate-limit headers. No 429 or 5xx was produced, so the
rejection could not be reproduced from this network.

What the code does today (`lib/core/net/live_quotes.dart` +
`lib/ui/screens/live_board_screen.dart`):

- estjt is fetched once per 60 s refresh (`_busy` prevents overlap), but it is
  started at the same time as **13 parallel** tgju archive downloads of 0.3–2.1
  MB each (≈15 MB per refresh). On a slow link those downloads starve the
  estjt request, which has a 15 s timeout.
- A timeout or any non-200 throws; `_fetchEstjt` converts it to an empty
  snapshot and sets `_estjtStale`. `mergeCells` carries the previous values
  forward, but on a cold start there is nothing to carry, so the whole column
  renders `—`.
- There is no backoff: a failing server is hit again 60 s later, forever.
- The carried-forward cells are not marked individually; only the column gets
  the `estjt قطع — آخرین مقادیر` strip, and there is no tgju fallback for a
  symbol estjt cannot serve.

Conclusion: the observed failures are consistent with (a) the 15 s client
timeout against a 4–9 s server under bandwidth contention, and (b) cold starts
with no last-good cache. The fix must therefore remove the bandwidth
contention, throttle/back off, keep last-good values with a visible badge, and
fall back to the same symbol's tgju value.

## Chosen fix (Phase 2)

1. Read tgju from `https://api.tgju.org/v1/widget/tmp?keys=…` (one 6 KB
   request, live `p`, CORS-enabled) instead of 13 archive downloads.
2. Put the currency on the row: `LiveBoardRow.isUsd = true` for `gold_ons` and
   `silver_ons`. USD rows are never divided; IRR rows are divided by 10 once at
   the fetch boundary. No per-symbol arithmetic.
3. Keep the daily archive only as an offline/failed-fetch fallback, still with
   row currency, and mark it stale.
4. estjt: one in-flight request, a minimum interval plus exponential backoff
   after failures, per-cell last-good values marked `کهنه`, and a tgju
   fallback marked `از tgju` when estjt has no value for a row.
5. Regression fixtures: the files in `test/fixtures/` captured above.

## Reproduce

```bash
curl -sS 'https://api.tgju.org/v1/widget/tmp?keys=ons,silver,silver_999'
curl -sS 'https://api.tgju.org/v1/market/indicator/summary-table-data/silver_999?lang=fa&order_dir=asc' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][-1])'
curl -sS -D - -o /dev/null 'https://www.estjt.ir/tv/'
```
