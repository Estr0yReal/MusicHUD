# Phase 5 — Reference Audit

Comparing the current Music HUD against the reference image, item by item.
Written **before** any Phase 5 code change, as a baseline for the before/after record.

Baseline snapshot: `.build-cache/baseline/playing.png`
(Phase 5 results: `docs/phase5/`)

The reference image was supplied at the start of Phase 1 and is not a file on disk, so
the "Reference appearance" column records the measurements and observations taken from
it at that time, which are reproduced in `README.md` and in the Phase 1 report.

---

## A. Window

| | |
|---|---|
| **Reference** | Borderless, no chrome, no title bar, transparent around a single rounded card. Desktop wallpaper visible through it, blurred. |
| **Current** | Borderless non-activating `NSPanel`, `isOpaque = false`, `backgroundColor = .clear`, no chrome. Behind-window `NSVisualEffectView` (`.hudWindow`). |
| **Difference** | None material. |
| **Priority** | **P3** |
| **Proposed** | No change. |

## B. Overall proportions

| | |
|---|---|
| **Reference** | Card aspect ≈ 1 : 1.4. Artwork ≈ 0.235 × card width. Spectrum height ≈ 0.195 × card width. Digit height ≈ 0.185 × card width. |
| **Current** | 300 × 428 → aspect 1 : 1.427. Artwork 0.233. Spectrum 0.193. Digits 0.183. |
| **Difference** | Within ~1 % on every ratio. |
| **Priority** | **P3** |
| **Proposed** | No change to the ratios. Confirm they hold at min/max window sizes. |

## C. Background

| | |
|---|---|
| **Reference** | Dark translucent frost; the wallpaper reads through clearly, including a blue cast in the upper-left. Not an opaque card. |
| **Current** | `NSVisualEffectView` `.hudWindow` at 0.72 opacity, black tint 0.42, plus a faint top-left sheen. |
| **Difference** | Close. The reference shows a little more of the wallpaper; the current tint is slightly heavy. |
| **Priority** | **P2** |
| **Proposed** | Try tint 0.42 → 0.38 and compare snapshots. Only keep if the reference match improves without hurting text contrast. |

## D. Album artwork

| | |
|---|---|
| **Reference** | Small, square, centred at the top. Slight rounding, a hairline edge, a restrained shadow. No coloured glow. |
| **Current** | 70 pt square (0.233 × width), radius 7, border `white 0.13` at 0.8 pt, shadow `black 0.38` radius 7 % of size, plus a top-edge white highlight. |
| **Difference** | Presentational only; close to the reference. |
| **Priority** | **P3** |
| **Proposed** | No change. |

## E. Track metadata

| | |
|---|---|
| **Reference** | Small centred title in letter-spaced capitals, a smaller grey `来自 <artist> · <place>` line beneath, then a full-bleed rule, then a three-row `标题 · 艺术家 · 专辑` list, left-aligned as a centred block. |
| **Current** | Matches that structure exactly: title 11.5 pt semibold tracked, subtitle 10 pt, three detail rows at 9.8 pt with a centred leading-aligned block. |
| **Difference** | Hierarchy is right. Long-text behaviour has **not** been verified with CJK, Greek or very long strings. |
| **Priority** | **P1** |
| **Proposed** | Verify truncation with the six required text cases and fix any layout break. |

## F. Digital clock

| | |
|---|---|
| **Reference** | Very large, bold, rounded-cap seven-segment digits `00:42:55`, near full-bleed, on a dark backplate, with a small centred caption below. Unlit segments are essentially invisible — the digits read as clean glowing strokes. |
| **Current** | 2048-style segment geometry is right (round caps, thickness 0.16 h, aspect 0.70). **Two defects found by zooming in:** |
| | 1. **The unlit "ghost" segments merge into a solid dark plate** filling each digit cell, instead of reading as faint individual segments. Seven strokes with round caps at 0.06 alpha union into a rounded rectangle. |
| | 2. **No glow at all** — only a drop shadow. The reference digits read as emissive. |
| **Priority** | **P0** (the clock is the visual focal point of the card) |
| **Proposed** | Draw ghosts as a single low-alpha path *without* letting the caps fill the cell (reduce thickness/alpha, or draw the outline rather than the stroke), and add a restrained outer glow to lit segments only. Must not bloom. |

## G. Playback controls

| | |
|---|---|
| **Reference** | Extremely restrained: a small `←` and the word `Previous` on the left, a tiny ghosted circular play/pause in the middle, `Next →` on the right. Low contrast. |
| **Current** | Same arrangement, 9.6 pt text, 21 pt ghost circle, hover brightening, real Music.app control. |
| **Difference** | Matches. **Missing accessibility labels** — VoiceOver sees only SF Symbol names. |
| **Priority** | **P1** (accessibility is explicitly required) |
| **Proposed** | Add `accessibilityLabel` to previous / play-pause / next and to the resize grip. |

## H. Spectrum

| | |
|---|---|
| **Reference** | Very fine, dense vertical bars, near full-bleed, rounded tops, smooth left-to-right decay, light grey with a soft haze. |
| **Current** | 48 log bands, gap ratio 0.45, radius = half bar width, vertical gradient (0.42 → 0.96 alpha), blurred haze pass at 0.28. Real FFT. |
| **Difference** | Shape and style match well. The reference bars read slightly **denser/finer** than 48 at this width. |
| **Priority** | **P1** |
| **Proposed** | Compare 48 / 64 / 72 side by side, and record CPU for each. Keep 48 unless a higher count is both visibly closer *and* within the performance budget. |

## I. Typography

| | |
|---|---|
| **Reference** | Small, letter-spaced, low-contrast Latin caps; nothing large except the digits. No heavy display font. |
| **Current** | System font throughout, sized from `HUDMetrics`. Digits are the only custom glyph construction. |
| **Difference** | Matches. No third-party font is used or needed. |
| **Priority** | **P3** |
| **Proposed** | No change. |

## J. Borders

| | |
|---|---|
| **Reference** | A hairline, barely visible edge on the card. |
| **Current** | 1 pt `white 0.085` stroke. |
| **Difference** | Matches. Must confirm it stays exactly 1 pt at 1× / 2× / non-integer scales. |
| **Priority** | **P2** |
| **Proposed** | Verify at three backing scales; fix only if a scale renders it as 2 px. |

## K. Shadows

| | |
|---|---|
| **Reference** | Restrained. The card sits on the desktop with a soft shadow; the artwork has a slight one. |
| **Current** | Window shadow from AppKit; artwork shadow `black 0.38`; digits use a small shadow inside the canvas. |
| **Difference** | Matches. |
| **Priority** | **P3** |
| **Proposed** | No change beyond the clock glow in F. |

## L. Glow / haze

| | |
|---|---|
| **Reference** | Two spots only: a soft haze around the spectrum bars, and the emissive quality of the lit digits. Nothing else glows. |
| **Current** | Spectrum haze present. **Clock glow absent.** |
| **Difference** | Covered by F. |
| **Priority** | **P0** (clock) / **P3** (rest) |
| **Proposed** | Add clock glow; leave everything else alone. |

## M. Spacing

| | |
|---|---|
| **Reference** | Tight and even; sections separated by full-bleed rules. |
| **Current** | All vertical rhythm comes from `HUDMetrics`, no magic numbers in views. |
| **Difference** | Matches. |
| **Priority** | **P3** |
| **Proposed** | No change. |

## N. Alignment

| | |
|---|---|
| **Reference** | Artwork, title, subtitle, rules and caption are centred; the detail list is a centred leading-aligned block; spectrum and digits are near full-bleed. |
| **Current** | Same. |
| **Difference** | Matches. |
| **Priority** | **P3** |
| **Proposed** | Confirm no drift at minimum size. |

## O. Interaction

| | |
|---|---|
| **Reference** | Static image; interaction is implied by the controls. |
| **Current** | Drag anywhere, corner grip to resize, hover states, real transport, status-bar menu, click-through mode. |
| **Difference** | Nothing missing. Resize stability and scale behaviour not yet verified. |
| **Priority** | **P1** |
| **Proposed** | Verify min/max sizes and 1× / 2× / non-integer scales for blurry digits, doubled hairline borders and spectrum clipping. |

---

## Summary

### P0 — clearly affects the overall look

1. **Seven-segment ghosts merge into a dark plate** filling each digit cell.
2. **Seven-segment digits have no glow**, so they do not read as emissive.

### P1 — clear detail differences

3. Metadata long-text behaviour unverified (CJK / Greek / very long).
4. Missing accessibility labels on the transport controls and the resize grip.
5. Spectrum density may be slightly lower than the reference (test 64 / 72).
6. Resize and backing-scale behaviour unverified.

### P2 — small details

7. Background tint possibly marginally heavy.
8. Hairline border at non-integer scales.

### P3 — not planned

9. Window, proportions, artwork, typography, spacing, alignment, shadows — already
   match the reference within measurement noise. **No change will be made**, per the
   rule that a change with no clear visual gain is rejected.

### Explicitly out of scope

* No Metal. Phase 4.5 measured the DSP at ~0.2 % and the audio thread at ~0.4 %; there
  is no evidence that Metal is needed.
* No new fonts, no third-party dependencies.
* No change to metadata, tap, ring buffer, FFT, `SpectrumFrame`, `SpectrumDisplay`,
  `AudioAnalysisEngine`, tap lifecycle or permission handling.
* No fake spectrum of any kind.
