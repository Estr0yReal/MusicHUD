# Phase 7 Report

Phase 7 proper has not yet been specified. This file currently records the
**pre-Phase-7 addition** requested before Phase 7 begins: the Shanghai World Clock
entry. It will be extended when the Phase 7 brief arrives.

---

## Addition — China / Shanghai World Clock

### Requirement

Add `Asia/Shanghai` to the World Clock, displayed as `SHANGHAI · CST`, using
`Foundation.TimeZone` for all time calculation, with no hand-written UTC offset
arithmetic and no new time-zone algorithm.

### Rotation

```
TRACK → TOKYO · JST → SHANGHAI · CST → LONDON · GMT/BST
      → NEW YORK · EST/EDT → LOS ANGELES · PST/PDT → TRACK
```

Shanghai sits second, immediately after Tokyo, in `WorldClockCatalogue.defaults`.

### Time-zone implementation

Nothing new was written. Shanghai goes through the **existing** strategy:
system abbreviation first, curated abbreviation only when the system returns a bare
offset, and DST always decided by the system.

Verified on this machine (macOS 15.5) before writing any code:

| Property | System value |
|---|---|
| `TimeZone(identifier: "Asia/Shanghai")` | resolves ✅ |
| `localizedName(.shortStandard)` | **`GMT+8`** — a bare offset |
| `secondsFromGMT` Jan / Jul | +8 h / +8 h |
| `isDaylightSavingTime` Jan / Jul | `false` / `false` — **no DST** |

Because the system returns the bare offset `GMT+8`, `WorldClockCity.isBareOffset`
matches and the curated `CST` is what reaches the display — exactly the path Tokyo
(`JST`) and London (`BST`) already used. No behaviour of the other four cities
changed.

### Settings

No new settings surface was needed — Shanghai is an ordinary catalogue entry, so it
already supports **enable, disable, reorder, delete and restore defaults** through the
existing World Clock section.

### Persistence and migration

Persistence still uses `MusicHUD.worldClock.v1`. A schema marker,
`MusicHUD.worldClock.schema`, was added so the introduction of Shanghai can be applied
**exactly once**.

The migration is **insertive, not a reset**: the new city is placed where it belongs in
the rotation (after Tokyo), and every existing entry keeps its position and its
enabled/disabled state. A user who has reordered their cities keeps their order.

Verified against a seeded "Phase 6 user" configuration
(`LA, TOKYO, LONDON(disabled), NEW YORK`, no schema key), launched for real:

| Check | Result |
|---|---|
| Order after migration | `LA, TOKYO, SHANGHAI, LONDON, NEW YORK` ✅ |
| Shanghai inserted after Tokyo | ✅ |
| User's reordering preserved (LA still first) | ✅ |
| Disabled state preserved (London) | ✅ |
| Schema marker written | `2` ✅ |

The once-only behaviour was then confirmed by deleting Shanghai and relaunching:
it was **not** resurrected. Without the marker, a deliberate deletion would be undone
on every launch — which is why the marker exists rather than a "is the new city
missing?" check.

### Tests

**233 tests, 0 failures** — up from 209. `Tests/MusicHUDCoreTests/ShanghaiClockTests.swift`
adds 24 tests covering all 12 requested cases plus the migration.

Offset and DST assertions are made against **real `Foundation.TimeZone`**, not
against literals this project could have got wrong:

| # | Case | Assertion |
|---|---|---|
| 1 | Can be created | `TimeZone(identifier:)` resolves; `isValid` |
| 2 | Abbreviation = CST | asserts the system gives a bare offset **and** that `CST` is produced |
| 3 | UTC offset = +8 h | `secondsFromGMT` in winter and summer |
| 4 | No DST | `isDaylightSavingTime` false both seasons; both curated abbreviations identical |
| 5 | 1 h from Tokyo | offset gap −1 h at both instants; rendered `08:00:00` vs `09:00:00` |
| 6 | 8 h from London in winter | +8 h winter, +7 h summer (BST), from the system |
| 7 | Gap to New York follows DST | 13 h winter / 12 h summer, and the change is asserted to come from **New York's** DST |
| 8 | Enters the cycle | second in the rotation; full walk wraps to Track |
| 9 | Can be disabled | skipped, both mid-cycle and while selected |
| 10 | Can be deleted | gone from the cycle, both mid-cycle and while selected |
| 11 | Restore defaults | Shanghai present, 5 cities |
| 12 | Persistence | save/reload round-trip including a reordered, partly-disabled list |
| — | Migration | insertive, non-duplicating, order-preserving, appends when Tokyo is absent, runs once |

Four existing tests hardcoded the old four-city rotation and were **updated, not
deleted**, to assert against the catalogue rather than a literal list — so adding a
sixth city later cannot silently break the walk. One of them also switched from
disabling "index 1" to disabling London **by identifier**, which is what it always
meant. Three assertions in my own first draft of the new tests were wrong (an
over-advancing loop, a `swapAt` that disabled the wrong city, and a magic catalogue
count); they were corrected in the tests, not worked around in the code.

### Snapshot

`docs/phase7/shanghai.png` — captured with the real app, real Music.app metadata and a
live FFT, then inspected.

| Check | Result |
|---|---|
| Caption reads `SHANGHAI · CST` | ✅ |
| Single line — no wrapping | ✅ (same 34 text rows as Tokyo and London) |
| No clipping | ✅ (generous margin both sides) |
| Clock digit size unchanged | ✅ (digit block height **70 px** identical across all three) |
| Card geometry unchanged | ✅ (border and corner strips pixel-identical to Tokyo) |
| Caption position, size, tracking, colour unchanged | ✅ |

Cross-check of the real values, all consistent with the unit tests:
`TOKYO · JST` 20:27:49 → `SHANGHAI · CST` 19:28:31 (**exactly 1 h behind**) →
`LONDON · BST` 12:29:14 (7 h behind, correct while London is on BST).

`docs/phase7/settings-worldclock.png` — the Settings → 时钟 world clock list showing
Shanghai alongside the others.

### Scope respected

Nothing outside the World Clock was touched. `WindowDragMath`, `WindowDragModifier`,
`AudioCaptureService`, the FFT, the ring buffer, `SpectrumView` and the Apple Music
integration are unchanged. No new architecture, no new time-zone maths, no UI change
made specifically for Shanghai.

---

## Phase 7 — macOS Native UX & Final Product Polish

Full detail is in `docs/phase7-native-ux-audit.md`; the pre-change state is in
`docs/phase7-baseline.md`. Summary below.

### Result

| | |
|---|---|
| Build | **0 errors, 0 warnings** (clean rebuild) |
| Tests | **245 tests, 0 failures** (233 → 245) |
| Package | `build/Music HUD.app`, ad-hoc signed, `codesign --verify --deep --strict` passes |
| Version | 1.0.0 (7) |
| Verdict | **ACCEPTED**, with one environment-caused limitation |

### Changes made (three, all small)

1. **Stale menu label removed.** The status menu had said
   `阶段：Phase 1 · 静态 UI 原型` since Phase 1 — six phases out of date and visible to
   the user. Now `版本 1.0.0 (7)`, read from `Info.plist` via a new `AppInfo`, so it
   cannot go stale again.
2. **Version bumped** to 1.0.0 (7) in the bundle.
3. **Bounded recovery for a stalled audio tap.** A tap can register with coreaudiod,
   have `AudioDeviceStart` return, and then deliver nothing while the source plays. The
   old guard (`capture == nil`) meant an existing-but-silent tap was never replaced, so
   the HUD could sit in `IDLE` for ever. Now: 8 s of silence from a started tap triggers
   a rebuild, up to 3 attempts, then an honest report. The policy lives in the pure,
   tested `TapRecoveryDecision`. A tap that has ever delivered is never rebuilt.

**Sixteen of the seventeen steps required no code change** — the behaviour was already
correct, and the brief says not to refactor what already works.

### Verified end-to-end, mechanically

* **Window recovery**: a frame saved at `(5000, 4000)` came back on screen at
  `(1582, 49)` with its size intact; a frame at `(1850, 300)` kept x = 1850 rather than
  being recentred.
* **No resource duplication**: 1 HUD panel + 1 status item, 1 `Starting capture`,
  10 threads, 0 residual processes after quit.
* **Tap recovery**: under a real stall, `rebuilding (attempt 1/3)` fired 9 s after
  `Device started`.
* **Permission honesty**: 135 s in `STARTING`/`IDLE` while the tap was demonstrably
  registered, and never once `PERMISSION DENIED`.
* **No microphone / Screen Recording**: confirmed absent from the built `Info.plist`.

### Known limitations

1. **Audio capture delivers no PCM in this environment right now.** OS-side and
   intermittent — the same binary delivered 42 s of audio earlier in the same session,
   and coreaudiod shows the tap registering. Affects both capture sources. The app no
   longer stalls on it, but the spectrum cannot be exercised here.
2. Consequently there is **no live-spectrum performance figure for Phase 7**; every
   reading was taken with no PCM. Phase 6.2's **8.5 % at 30 FPS** remains the last valid
   measurement.
3. **GUI-driven interaction was not exercised mechanically** — synthetic mouse events
   need Accessibility permission, which is not granted. Menu hide/show and the Phase 6.1
   click-vs-drag case still need a human.
4. Only **1× backing scale** is available now; 2× was validated in Phases 5–6.
5. The repository still has **no git commits**, so no diff can be produced from it.
