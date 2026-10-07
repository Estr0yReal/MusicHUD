# Phase 4.5 — Performance & Visual Architecture Audit

Scope: **measurement and targeted fixes only.** No features were added, no Phase 5
work was started, and nothing was changed that could not be shown to help.

Measured on macOS 15.5, Apple Silicon (E-core / P-core mix), Music.app playing
48 kHz stereo through a Core Audio process tap.

---

## 1. Method, and why the obvious approach was wrong

**`ps -o %cpu` is not usable here.** It reports an average over the process's whole
lifetime, so a scenario measured ten seconds after launch is dominated by startup
cost. Comparing scenarios with it produced numbers that did not reproduce.

`top -l n -s 1` looked like the answer but silently truncates its sample series, so
a 17-sample request yielded 3 usable readings.

What the audit actually uses:

| Tool | Purpose |
|---|---|
| `scripts/cpu-sample.py` | CPU from cumulative `ps -o time=` deltas across a window; exact and reproducible |
| `scripts/audit-measure.sh` | Applies a scenario through the app's own persisted settings, launches, waits for steady state, measures |
| `xcrun xctrace` (Time Profiler) | Per-thread CPU attribution for the traces below |

Two methodological traps worth recording, because both produced wrong answers before
being caught:

* **`cfprefsd` caches preferences.** Writing the settings plist directly from Python
  is silently ignored by the running app. An early "HUD hidden" run therefore measured
  the HUD *on screen*. Settings are now written through `defaults write … -data`.
* **Verifying a scenario afterwards is not verifying it.** A window check taken after
  the last scenario in a loop described that scenario, not the one being measured.

Every scenario below was confirmed to have reached steady state (`RECEIVING AUDIO`,
tap created ~0.06 s) before its numbers were accepted.

---

## 2. Scenario matrix

A = HUD hidden · B = pipeline stopped · C/D/E = HUD + spectrum at 20/30/60 FPS ·
F = music paused.

| Scenario | Before | After | Change |
|---|---|---|---|
| **A** HUD hidden, playing, 30 FPS | 9.44 % | **7.12 %** | −25 % |
| **C** HUD + spectrum, 20 FPS | 6.72 % | **5.38 %** | −20 % |
| **D** HUD + spectrum, 30 FPS *(default)* | 9.28 % | **7.13 %** | −23 % |
| **E** HUD + spectrum, 60 FPS | 17.44 % | **13.50 %** | −23 % |
| **F** music paused, HUD visible | 10.50 % | **1.50 %** | **−86 %** |
| — no Music.app running, HUD hidden | 6.62 % | **1.25 %** | **−81 %** |

Peak RSS is 53–66 MB in every scenario. The ring buffer never overflowed
(`Ring Overflow 0` throughout).

---

## 3. The finding that reframed everything

The audit question was "why is CPU ~9.5 % when the spectrum is not drawn?". The
answer was not where Phase 4 assumed.

**The HUD's rendering is essentially free.** With the HUD *hidden* — no window, no
Canvas, no compositing — the app still cost **9.44 %**. Hiding or showing the HUD
changed the number by about 0.2 %.

So the cost was never the drawing. It was the fact that the pipeline was publishing
state 30 times a second **whether or not anything had changed, and whether or not
anything was listening.**

The decisive experiment:

| Condition | CPU |
|---|---|
| HUD hidden, music playing (audio flowing) | 9.44 % |
| HUD hidden, **Music.app not running** (no tap, no PCM) | 6.62 % |

6.6 % of CPU with no audio and no visible window. That is pure waste, and it pointed
straight at the publish path.

### Why every frame looked "new"

`AudioAnalysisEngine.makeFrame` stamps each frame with `timestamp: .now`. Two
consecutive frames were therefore never equal, so any equality-based short-circuit
was impossible and `@Published` fired on every tick, forever:

```swift
// before
spectrum = frame          // @Published — fires unconditionally
```

SwiftUI's AttributeGraph dutifully invalidated, and the view tree re-rendered an
invisible window 30 times a second.

---

## 4. Instruments: where the CPU actually went

`xcrun xctrace record --template 'Time Profiler'`, attached to the app, exported with
`xctrace export --xpath '…/table[@schema="time-profile"]'` and aggregated by thread
state and leaf frame.

**Scenario: music paused, HUD hidden, 593 samples / 10 s ≈ 5.9 % CPU**

| Symbol | Share |
|---|---|
| `AG::Graph::UpdateStack::update()` + `propagate_dirty` + `Subgraph::update` — SwiftUI AttributeGraph | ~3.5 % |
| `CA::Context::commit_transaction`, `CA::Layer::collect_layers_` — Core Animation commit | ~1 % |
| Swift runtime churn (`swift_retain`, `getCache`, `objc_msgSend`, `_CFRetain`) | ~1 % |
| **`AudioAnalysisEngine.ingest` (the audio thread)** | **0.4 %** |

The audio thread and the DSP were never the problem. The FFT itself is
**0.02–0.08 ms per tick** — at 30 ticks/s that is roughly **0.2 % CPU**. The cost was
SwiftUI being woken for nothing.

---

## 5. Three sites of the same defect

Unconditional `@Published` assignment turned up in three places, all with the same
mechanism and all invisible to functional testing:

1. **`SpectrumDisplay` / `spectrum = frame`** — the timestamp made every frame unique,
   so the renderer was invalidated on every tick even with silence and no window.
2. **`state = .silent` and `statusDetail = …`** — written 30×/s while already
   `.silent`. Mirrored into `AppState.captureState`, which the **whole HUD** observes,
   so this re-rendered the entire card, not just the spectrum.
3. **`AppState.providerDidUpdate`** — `snapshot`, `availability` and `sessionElapsed`
   were written on every provider callback even when the values were identical.

A fourth, structural issue compounded them:

4. **`SpectrumView` observed the whole `AudioCaptureService`**, which publishes a
   dozen unrelated diagnostics values. *Any* counter moving invalidated the spectrum
   Canvas.

---

## 6. Changes made

Four changes, each justified by a measurement above. All are behaviour-preserving:
the displayed pixels and numbers are identical.

**1. Publish the spectrum only when the drawn values change.**
A new `SpectrumDisplay` carries exactly one property and compares `bands`, `rms` and
`peak` — deliberately *not* the timestamp. `SpectrumView` now observes that instead of
the service, so diagnostics counters can move as much as they like without touching the
render path.

**2. Assign capture state only on a real transition.**
`state` and `statusDetail` are guarded by equality before assignment.

**3. Guard the mirrored state in `AppState`.**
`snapshot`, `availability` and `sessionElapsed` are compared before being written.

**4. Guard the diagnostics counters.**
`fftMilliseconds` (0.005 ms threshold), `peakHold` (0.001 threshold, far below one
pixel of meter travel) and `overflowCount` no longer republish identical values.

**Explicitly not changed**, because the evidence did not support it:

* **The vibrancy / `NSVisualEffectView` blur.** It was a prime suspect, so it was
  measured directly by disabling it: **14.4 % vs 15.5 %** — about 1 %, not the cause.
  Left alone.
* **The Canvas haze blur.** Also measured by removing it: ~13.7 % vs ~14.4 %. Kept,
  because it is what gives the band its soft edge and it costs very little.
* **The 30 FPS default.** Retained; 60 FPS still costs ~2× and remains selectable.
* **The audio thread, ring buffer, FFT, tap lifecycle, Apple Music metadata and window
  behaviour.** Instrumentation showed the audio thread at 0.4 % and the FFT at 0.2 %;
  there was nothing to gain and everything to lose.

---

## 7. Visual impact

**None.** `docs/snapshot-spectrum.png` and the post-audit snapshot are pixel-comparable:
same artwork, same type, same spectrum shape, same clock. The smoothing remains
frame-rate independent, so 20/30/60 FPS still look identical to each other.

---

## 8. Test results

```
swift build : 0 errors, 0 warnings
swift test  : 155 tests, 0 failures
```

All 155 Phase 4 tests are retained unchanged and pass. No test asserts on publish
counts, so none of the optimisations are "verified" by weakening a test.

---

## 9. Remaining limitations

* **Playing audio still costs ~7 % at 30 FPS and ~13.5 % at 60 FPS.** That is not
  waste: the picture genuinely changes every frame, so the invalidation is real. The
  DSP is ~0.2 % of it; the rest is SwiftUI presenting a vibrancy-backed window.
  Getting below that would mean drawing the spectrum outside SwiftUI, which is a
  Phase 5 architectural question, not an audit fix.
* **Idle cost is now ~1.25 %**, which is the audio pipeline, the 1 Hz supervisor and
  the 1.5 s Music.app poll. Nothing obvious is left to remove there.
* **Absolute numbers are noisy on this machine** (load average 5–6.5 during the audit,
  other applications active). The *relative* improvements are large enough — 80 % in
  the idle cases — to be well outside that noise, but the third significant figure of
  any single row should not be treated as precise.
* **Scenario B** ("HUD shown but spectrum not drawn") only became a measurable state
  *after* the spectrum publish was made conditional; before the fix the spectrum was
  redrawn unconditionally, so no such state existed. It is reported here as the
  "paused" and "no Music" rows.
* **The audit harness itself is new code** (`scripts/audit-measure.sh`,
  `scripts/cpu-sample.py`). It is a measurement tool, not a product feature, and it is
  the only thing this phase added.
