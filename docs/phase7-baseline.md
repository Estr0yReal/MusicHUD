# Phase 7 — Baseline Audit (STEP 0)

Recorded before any Phase 7 functional change. Nothing in this document was
established by reading code alone; every runtime figure was measured.

---

## 1. Environment

| Item | Value |
|---|---|
| macOS | 15.5 (24F74) |
| Architecture | arm64 (Apple Silicon) |
| Swift | 6.1.2 (swiftlang-6.1.2.1.2), target `arm64-apple-macosx15.0` |
| Display | 1920 × 1080, **backing scale 1.0** (single screen) |
| Audio output | `MacBook Air扬声器` (built-in), `runningSomewhere = true` |
| Other audio device present | `H24F8` (the monitor) — new since Phase 5 |

## 2. Repository / build

| Item | Value |
|---|---|
| git | **no commits** — the working tree has never been committed |
| Build | `swift build` → 0 errors, **0 warnings** |
| Tests | **233 tests, 0 failures** |
| Source size | 65 files / 12 108 lines |

> Note: the Phase 7 brief states the baseline is 209 tests. That was true at the end
> of Phase 6.2. The pre-Phase-7 Shanghai addition took it to **233** (+24).

## 3. Window

| Item | Value |
|---|---|
| Default size | 300 × 428 (design 300 × 420) |
| Current size | 314 × 451 (persisted user frame) |
| Minimum | 240 × 348 |
| Maximum | 900 × 1400 |
| Aspect | 1 : 1.427 |
| Level | `layer = 3` (floating panel) |

## 4. Runtime, audio not flowing

| Item | Value |
|---|---|
| CPU | ~2.0–2.5 % (median) |
| RSS | 49.6–57.9 MB |
| Threads | 10 |

## 5. Permission states

| Permission | State | Evidence |
|---|---|---|
| System Audio Recording (`kTCCServiceAudioCapture`) | **granted** | a process tap registers with coreaudiod, which it cannot do while denied |
| Music automation (Apple Events) | **granted** | metadata and transport work |
| Microphone | **not requested, not used** | absent from `Info.plist` |
| Screen Recording | **not requested, not used** | absent from `Info.plist` |

## 6. Current menu-bar behaviour

Rebuilt on every open (`menuNeedsUpdate`), so checkbox state is never stale:

```
显示 HUD / 隐藏 HUD
────────────
窗口层级  (normal / floating / desktop, radio)
────────────
鼠标穿透模式  (checkbox)
重置窗口位置
────────────
设置…            ⌘,
音频诊断…        ⌘D
────────────
来源：<source>
阶段：Phase 1 · 静态 UI 原型      ← STALE
────────────
退出 Music HUD   ⌘Q
```

**Finding (P1): the "阶段" item still says `Phase 1 · 静态 UI 原型`.** Six phases stale.
It is user-visible and factually wrong, and is in scope for STEP 1.

Everything STEP 1 requires is otherwise already present: show/hide, Settings…, Quit,
no duplicate window creation, and the menu is rebuilt per open.

## 7. Current settings behaviour

Six tabs, each with titled sections: 音乐 / 外观 / 频谱 / 时钟 / 窗口 / 状态.
Persistence via `HUDSettingsStore` (`MusicHUD.settings.v1`) and a separate
`MusicHUD.worldClock.v1` + `MusicHUD.worldClock.schema`.

## 8. Current window persistence

`HUDWindowController` restores the saved frame and passes it through
`WindowBehavior.clampedToVisibleScreen`, which:

* keeps the frame if it intersects **any** screen's `visibleFrame` (8 pt tolerance);
* otherwise repositions it to the default origin on the preferred screen;
* **preserves `frame.size`** in both cases.

This already satisfies STEP 3's requirement. It is verified by unit test in Phase 7.

## 9. FINDING (P0) — audio capture is currently not delivering PCM

**This is the most important baseline observation, and it is reproducible.**

Two consecutive launches with Music.app *playing*:

| Stage | Observed |
|---|---|
| `Tap created` | at **60 s** (one run) — tap creation itself blocked |
| `Device started` | after **30 s** (`Device started (30.01s)`) |
| PCM | **never arrives** — stuck at `[IDLE] 音频设备已就绪，正在等待音源输出` |
| Second and third launches | `Device started` had still not returned after 80 s |

coreaudiod's own log shows the tap **registering successfully** and unregistering only
when the app was killed:

```
HALS_MultiTap_Engine::RegisterIOContext: registering IOContext 11280
HALS_MultiTap::register_autostart_context: registering IOContext 11280
   … 80 s later, on app termination …
HALS_MultiTap::unregister_meta_device: unregistering IOContext 11273
HALS_MultiTap_Engine::UnregisterIOContext: unregistering IOContext 11280
```

**Therefore this is not a permission failure.** The registration succeeds; buffers
simply never arrive. The audio environment itself is healthy — the default output
device is running, and Music.app reports `playing`.

This is OS-side, and the same binary delivered 42 s of `RECEIVING AUDIO` earlier in
the same session, so it is intermittent rather than a code regression.

**The app-side gap it exposes (in scope for STEP 7):** once a tap exists,
`attemptTapIfDue()` is guarded by `capture == nil`, and `isSettingUpTap` stays true for
as long as setup is in flight. So an attempt that registers but never delivers is
**never retried** — the HUD can sit in `IDLE` indefinitely even though Music is
playing. That is the one part of this that the app can and should address.

**What the app already does right:** it reports `STARTING` honestly rather than
claiming `PERMISSION DENIED` (the Phase 5 fix holds), it stays responsive, and it burns
~2 % CPU rather than spinning.

## 10. Areas audited, no change needed

| Area | State |
|---|---|
| `AppDelegate` lifecycle | menu delegate rebuilds state per open |
| `HUDWindowController` | single instance, off-screen recovery present |
| `AppState` | owns one `AudioCaptureService` |
| `HUDSettings` / store | schema-stable, world clock on its own key |
| Accessibility | 11 labels on transport, clock and resize grip |
| Keyboard | `⌘,` Settings and `⌘Q` Quit already bound in the menu |
| Drag | Phase 6.2 screen-coordinate model, `WindowDragMath` — **frozen** |
