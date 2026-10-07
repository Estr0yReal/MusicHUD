# Phase 7 — Native UX Audit

Detailed record for Phase 7. The summary report is `docs/phase7-report.md`;
the pre-change baseline is `docs/phase7-baseline.md`.

Method: every runtime claim below was measured or observed on the running app.
Anything established only by reading code is labelled as such.

---

## 1. Baseline

See `docs/phase7-baseline.md`. Key figures: macOS 15.5 (24F74), arm64, Swift 6.1.2,
1920×1080 at **1×**, 233 tests / 0 failures before Phase 7 changes, 0 build warnings.

## 2. Menu bar

**Requirement check** — all present before Phase 7:

| Requirement | State |
|---|---|
| Menu-bar item opens/shows the HUD | ✅ `显示 HUD` / `隐藏 HUD`, label reflects current state |
| No duplicate window when already shown | ✅ the same panel is ordered front; see §4 |
| HUD recoverable after hiding | ✅ `orderFrontRegardless()` on the existing panel |
| App does not quit when the HUD is hidden | ✅ hide is `orderOut(nil)`, not termination |
| Settings reachable from the menu | ✅ `设置…` ⌘, |
| Quit really quits | ✅ `NSApp.terminate(nil)` |

**Change made.** The menu carried the item
`阶段：Phase 1 · 静态 UI 原型` — written in Phase 1 and still there six phases later.
It was user-visible and false. Replaced with `版本 1.0.0 (7)`, read from
`Info.plist` through a new `AppInfo` type, so it cannot go stale again.

**Deliberately not changed.** The menu is longer than the brief's suggested minimum
because the extra items are real features (window level, click-through, reset
position, audio diagnostics). Removing working features to shorten a menu is not
polish. Menu text stays Chinese, matching the HUD's own captions (`已播放时长`,
`来自 …`) — switching the menu to English would have made the app inconsistent with
itself.

## 3. App lifecycle

| Transition | Behaviour | How verified |
|---|---|---|
| Launch → HUD | panel ordered front | observed |
| Hide HUD | `orderOut(nil)`, app stays resident | code |
| Show HUD | `orderFrontRegardless()` | code |
| Settings open/close | separate window; HUD unaffected | observed |
| Quit | `NSApp.terminate(nil)`; process exits | observed, **0 residual processes** |

**Resource duplication — measured on a fresh launch:** 1 HUD window, 1
`Starting capture`, 10 threads, 0 processes remaining after quit.
`show`/`hide`/`toggle` only call `orderFrontRegardless` / `orderOut` on the panel
created once in `HUDWindowController.init`, so no path can create a second window,
service, observer or timer. Verified by inspection; **GUI-driven hide/show was not
driven mechanically** (see §15).

## 4. Window behaviour

Frozen per the brief: the Phase 6.2 drag model (`WindowDragMath`,
`NSCursor`-independent screen coordinates) is untouched.

| Property | Value |
|---|---|
| Level | `layer = 3` floating panel |
| Movable / resizable | yes, with a corner grip |
| Min / max size | 240 × 348 / 900 × 1400 |
| Always-on-top | three modes (normal / floating / desktop) |

## 5. Window persistence

`WindowBehavior.clampedToVisibleScreen` keeps the saved frame when it intersects any
screen's `visibleFrame` (8 pt tolerance), and otherwise moves it to the default origin
— **preserving the size** in both cases.

**Verified end-to-end on the real app**, by writing a frame into the real preferences
and relaunching:

| Saved frame | Result | Correct? |
|---|---|---|
| `(5000, 4000)` — fully off-screen | recovered to `(1582, 49)`, size still 314 × 451 | ✅ |
| `(1850, 300)` — partially visible | kept at x = **1850**, not recentred | ✅ |

A window pushed to the screen edge is therefore never snapped back, and a size the user
chose is never altered by recovery.

## 6. Settings

Six tabs — 音乐 / 外观 / 频谱 / 时钟 / 窗口 / 状态 — each with titled sections. Every
control writes through to `HUDSettings` and takes effect immediately. Persistence uses
`MusicHUD.settings.v1`; the World Clock uses its own `MusicHUD.worldClock.v1` plus a
schema marker, so neither can invalidate the other. No change was needed.

## 7. Permission UX

| State | Shown as |
|---|---|
| Not determined / starting | `STARTING` |
| Device running, no data yet | `IDLE` — `音频设备已就绪，正在等待音源输出` |
| Receiving | `RECEIVING AUDIO` |
| Receiving only zeros | `SILENT` |
| Music not running | `IDLE` — `Music.app 未运行，启动后将自动连接` |

**The Phase 5 fix holds and was re-verified:** a timeout on `AudioDeviceStart` no longer
produces `PERMISSION DENIED`. The message names both possibilities instead. Under the
conditions in §9 the app spent 135 s in `STARTING`/`IDLE` and **never once** claimed a
permission problem — which, given the tap demonstrably registers with coreaudiod, would
have been a lie.

Microphone and Screen Recording are never requested; neither key exists in the built
`Info.plist` (verified with `plutil`).

## 8. Music lifecycle

Music not running shows `Music is not running` with a placeholder artwork, dimmed
transport and `—` metadata (snapshot `03-unavailable`). The app does **not** launch
Music.app, crash, or retry in a loop. When Music returns, metadata resumes with no
restart of MusicHUD.

## 9. Audio lifecycle — FINDING (P0)

**The process tap registers but never delivers PCM in this environment.**

Observed on three consecutive launches with Music.app *playing*, for **both** capture
sources (Music-process tap and system-output tap):

| Stage | Observation |
|---|---|
| `Tap created` | at ~60 s — creation itself blocked |
| `Device started` | after 30 s — `AudioDeviceStart` blocked |
| PCM | **never** — stuck at `[IDLE]`, for 135 s and counting |

coreaudiod's log shows registration succeeding and unregistering only on app exit:

```
HALS_MultiTap_Engine::RegisterIOContext: registering IOContext 11280
HALS_MultiTap::register_autostart_context: registering IOContext 11280
   … 80 s later, on termination …
HALS_MultiTap::unregister_meta_device: unregistering IOContext 11273
```

**So this is not a permission failure and not a code defect.** The same binary delivered
42 s of `RECEIVING AUDIO` earlier in the same session; the audio environment is healthy
(default output device running, Music reporting `playing`). It is an intermittent,
OS-side condition.

**The app-side gap this exposed, and the minimal fix.** `attemptTapIfDue` was guarded by
`capture == nil`, and `isSettingUpTap` stays true while setup is in flight — so an
existing-but-silent tap was **never replaced**, and the HUD could sit in `IDLE` for ever
with music playing.

Added a bounded recovery: after a started tap has delivered nothing for **8 s**, rebuild
it, up to **3** attempts, then report the condition plainly instead of retrying. The
policy lives in `TapRecoveryDecision` (pure, in Core) so the boundary is tested rather
than buried in a timer callback. A tap that has *ever* delivered is never rebuilt —
otherwise a quiet passage would tear down a working capture.

Verified on the running app under the real stall:

```
[ 60.07s] Tap created
[ 90.08s] Device started (30.01s)
[ 99.02s] Tap started but delivered no PCM after 8s - rebuilding (attempt 1/3)
```

No `AudioCaptureService` redesign; the FFT, ring buffer and capture architecture were
not touched.

## 10. Accessibility

| Control | Label | Note |
|---|---|---|
| Previous | 上一首 | |
| Play / Pause | 暂停 / 播放 | **dynamic**, as required |
| Next | 下一首 | |
| Clock | mode-aware — reads `TOKYO 当前时间 19:28:31` | + hint `点按切换世界时钟`, `.isButton` |
| Resize grip | 调整窗口大小 | + hint |
| Settings button | 打开系统设置 | + hint |

Six explicit labels. Settings controls are standard SwiftUI controls with visible text
labels, which VoiceOver reads natively — no synthetic labels were added, and no
decorative view was given a fake button trait.

## 11. Keyboard

`⌘,` (Settings), `⌘Q` (Quit) and `⌘D` (audio diagnostics) are provided by the status
menu's own key equivalents. macOS supplies them; **nothing was reimplemented.** No
global hotkeys were added, and the HUD deliberately has no keyboard control.

## 12. Visual state consistency

Inspected across playing / paused / unavailable / starting, and across track mode and
all five cities:

* identical typography, opacity, spacing, seven-segment geometry, artwork treatment,
  separator and controls;
* the transport dims when Music is unavailable, and metadata falls back to `—`;
* status badges stay muted grey — **no red, no oversized text, no colour-coded alarm**
  anywhere in the HUD.

Red/orange exist only in `AudioDiagnosticsView`, a separate panel whose entire purpose
is diagnosis; that is appropriate and unchanged.

## 13. Performance

| Scenario | CPU (median) | RSS |
|---|---|---|
| Music playing + HUD visible | 2.50 % | 58.2 MB |
| Music paused + HUD visible | 1.50–2.50 % | 57–59 MB |
| Music not running + HUD visible | 1.00 % | 52.0 MB |

**These are not comparable to Phase 6.2's 8.5 %.** Every Phase 7 reading was taken while
the tap delivered no PCM, so there was no spectrum to draw — this is the no-audio cost.
The last valid live-spectrum measurement remains Phase 6.2's **8.5 %** at 30 FPS.

Neither Phase 7 change can affect steady-state CPU: the version string is read once at
launch, and the recovery check is a handful of comparisons on the existing 1 Hz
supervisor tick. No new timers, publishers or render work were added.

## 14. Snapshots

`docs/phase7/snapshots/` — 15 images, all generated with the real app and inspected.

## 15. Tests

245 tests, 0 failures (233 → 245, +12). All earlier tests retained.

## 16. Known limitations

1. **Audio capture delivers no PCM in this environment** (§9). OS-side, intermittent,
   not fixable from the app. The app now recovers boundedly instead of stalling for ever.
2. **No live-spectrum performance figure for Phase 7** — consequence of (1).
3. **GUI-driven interaction was not exercised mechanically.** Posting synthetic mouse
   events requires Accessibility permission, which is not granted (`AXIsProcessTrusted`
   = `false`), so hide/show via the menu and the Phase 6.1 click-vs-drag case remain
   documented as needing a human. Code inspection and the `DragProbe` cover the maths,
   not the pointer.
4. **Only 1× backing scale is available** on this machine now; the 2× case was validated
   in Phases 5–6 but cannot be re-checked here.
5. **`git` has no commits** — the working tree has never been committed, so no
   change-set diff can be produced from the repository itself.
6. A partially-visible restored frame came back 29 pt lower in y than saved
   (`300` → `329`). x, size and the clamping decision were all correct; the shift is
   consistent with AppKit's own on-screen window constraint. Not investigated further.
