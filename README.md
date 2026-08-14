# swipewise

> **Greedy per-transaction card routing leaves `X%` of reward value unclaimed versus
> optimal cycle allocation, measured over `N` real statement cycles.**
>
> ⚠️ `X` and `N` are unmeasured. This project is at **v0**. The claim above is the
> thing being built toward, not a result. It gets filled in once it is measured, or it
> does not go in this README at all.

An on-device Flutter app that reads your credit-card statement PDFs, works out what each
transaction actually earned, and answers *"which card do I use for this purchase, and
what do I get?"* — then reconciles each cycle and reports the reward value you left on
the table.

**Everything happens on the device.** No backend, no account, no upload. The only
network call the app ever makes fetches a signed, public reward-rules bundle that
contains no user data.

---

## Status

Repo initialized 2026-08-13. Engine scaffold only — analysis, formatting, the purity
guard and the test suite all pass on Dart 3.13, but no parsing logic exists yet.

| | |
|---|---|
| Current version | v0 — parser spike, not started |
| Target issuer for v0 | SBI Card |
| Next gate | ≥95% row-extraction accuracy on 5 statements |

---

## Layout

```
packages/
  pdf_glyph_source/   pure Dart — PDF bytes → positioned glyph runs (PDFium/FFI)
  statement_parser/   pure Dart — glyph runs → rows → columns → transactions
  rewards_engine/     pure Dart — rule evaluator (cap buckets) + cycle optimizer
tools/
  check_purity.dart   CI guard: the packages above must never import Flutter
fixtures/             glyph dumps + hand-labeled ground truth
app/                  (not created yet) Flutter shell
```

**Nothing derived from a real statement is committed.** `fixtures/statements/raw/` and
`fixtures/glyphs/raw/` are gitignored; only redacted material is tracked. Redaction
happens at the glyph level — substitute names and card numbers in the JSON while
keeping every `x/y/w/h` and every character count intact, because the geometry *is* the
test.

All three `packages/` are **pure Dart with zero Flutter dependencies**, so PDF
extraction, parsing, evaluation and optimization all run in a plain `dart test` on CI
with no device and no emulator. That boundary is enforced, not just documented —
`tools/check_purity.dart` fails the build if any of them acquires a Flutter dependency
or a `package:flutter/` import.

Extraction reaches native code (PDFium through `dart:ffi`) without breaking that rule,
because `pdfrx_engine` is Flutter-free and its PDFium binary arrives through a Dart
build hook at build time — not a runtime network call.

---

## Development

```bash
dart pub global activate melos
melos bootstrap
melos run analyze
melos run test
melos run check:purity
```

---

## Non-goals

- **No financial advice.** The app surfaces what a reward rule says. It never
  recommends acquiring a card.
- **No scraping.** No bank portal automation, no RBI Account Aggregator integration.
  User-supplied PDFs only.
- **No backend, no analytics, no crash reporting** that touches transaction data.
- **No charting library.** Every visualization is hand-written `CustomPainter`.
