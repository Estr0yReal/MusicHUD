# Phase 7.1 — Release Readiness

## 1. Launch at Login

Implemented with **`SMAppService.mainApp`** (`ServiceManagement`). No
`LSSharedFileList`, no `SMLoginItemSetEnabled`, no LaunchAgent, no shell script, no
crontab, no third-party helper, no private API.

**The toggle reads live system state, never a cached bool.** `LaunchAtLogin.status`
maps `SMAppService.mainApp.status` on every read, because the user can change the login
item in System Settings without telling the app.

| System status | Shown as | Toggle |
|---|---|---|
| `.enabled` | Registered with macOS | on |
| `.notRegistered` | Not registered | off |
| `.requiresApproval` | Waiting for approval in System Settings | **on** |
| `.notFound` | The app must be in /Applications | off |
| register/unregister throws | Registration failed: … | off |

`requiresApproval` deliberately reads as **on**: the registration was accepted and macOS
is waiting for the user; showing "off" would misreport what happened. When approval or a
missing bundle is the state, the panel offers a button that calls
`SMAppService.openSystemSettingsLoginItems()`.

**No duplicate registration:** `enable()` returns early when the status is already
`.enabled` or `.requiresApproval`, and `disable()` returns early when already
`.disabled`. Re-registering an already-registered app is exactly how duplicate login
items get created, so it is guarded explicitly rather than left to the API.

The testable part — the state→toggle mapping and the localisation key for each state —
lives in Core as `LoginItemStatus`, so it is unit-tested without touching real system
state. The `SMAppService` calls themselves are **not** unit-tested, because a test must
not register a real login item; that is recorded as manual verification.

## 2. Development UI removed

Removed from the Settings window:

* the entire **「本阶段（Phase 2）说明」** section, including *已接入真实数据…*,
  *仍未实现*, *实时音频捕获（Phase 3）*, *真实 FFT 频谱（Phase 4）* and the demo-data
  disclaimer;
* a **second, duplicated copy** of the same block that had accumulated inside another
  tab;
* a user-visible **`Phase 3 · PCM → RMS / Peak · 未接入频谱，未做 FFT`** banner in the
  audio diagnostics panel — which was not only developer text but **factually wrong**,
  since the app has had a real FFT since Phase 4;
* a stale code comment referring to the "Phase 2 tab".

Verified: **0 user-visible Phase strings remain** anywhere in `Sources/`.

## 3. Status page

Rebuilt around what a user actually needs, with every value live:

| Section | Rows |
|---|---|
| Now Playing | Music state, Audio Capture state, Source |
| Spectrum | FFT (`2048 points / hop 512`), Bands, Sample Rate, FFT Time, UI Frame Rate, Ring Buffer Overflows |
| Music | permission state, with a button to System Settings when Automation is missing |

No developer notes, no test information, no phase text.

## 4. Localization architecture

**SwiftPM cannot compile String Catalogs.** Verified directly: a `.xcstrings` file is
copied verbatim into the resource bundle and `String(localized:bundle:)` returns the raw
key. Compilation into `.lproj` only happens in Xcode builds. The shipping mechanism is
therefore **`en.lproj` / `zh-Hans.lproj` `Localizable.strings`** — still an Apple-native
mechanism, still key-based, still no `if language ==` branches and no string dictionary.

* **SwiftUI** uses `Text("some.key")`; the root view carries `.environment(\.locale, …)`
  so a language change re-renders immediately.
* **AppKit** (the status menu) does not read the SwiftUI environment, so it resolves
  through `L(state, "menu.quit")`, which reads the same tables explicitly. The menu is
  rebuilt on every open, so it picks up a change at once.
* **Core** holds no display text: enums expose `localizationKey` and the app decides how
  to say it.
* SwiftPM **lowercases** `.lproj` directory names in the built bundle
  (`Bundle.module.localizations` → `["zh-hans", "en"]`), so `LocalizationBundle` tries
  both the canonical and lowercased names. This was found empirically, not assumed.

`build-app.sh` copies the `.lproj` directories into `Contents/Resources/`, which is what
`Bundle.main` resolves against.

**156 keys in each language**, covering the HUD, transport, capture states, status page,
all settings tabs, the menu bar, permissions, cities and error text.

## 5. Language setting

A new **General** tab holds a segmented Language picker (each language named in its own
script — `English` / `中文`) and the Launch at Login toggle.

* Stored under **its own key** (`MusicHUD.language.v1`), deliberately not added to
  `HUDSettings`: a new field there would make every existing settings blob fail to decode
  and silently reset the user's window position and audio source.
* **First launch follows the system language**; `zh`, `zh-Hans`, `zh-CN`, `zh-SG` select
  Chinese. `zh-Hant`/`zh-TW`/`zh-HK` fall back to **English** rather than showing the
  wrong script. Anything unsupported falls back to English.
* **An explicit choice always wins** and is never overwritten on a later launch.
* Switching is immediate; no restart.

## 6. Time zones

Unchanged. Still `Foundation.TimeZone` with IANA identifiers, no hand-written offsets,
DST from the system database. Cities gained localisation keys for their display names
(`东京` / `TOKYO`), so Chinese shows `东京 · JST` and English shows `TOKYO · JST`.

## 7. Tests

**264 tests, 0 failures** — up from 245. `ReleaseReadinessTests` adds 19:

* **Language**: first-launch system detection; all six Chinese identifiers map to
  Chinese; traditional Chinese falls back to English; unsupported languages fall back;
  first supported system language wins; explicit choice beats the system; repeated
  resolution is stable across launches.
* **Persistence**: unset is `nil` (not a default); round-trip; clear; **and the
  regression the brief calls out** — storing a language leaves `MusicHUD.settings.v1`
  and `MusicHUD.worldClock.v1` byte-identical.
* **Launch at login**: `requiresApproval` reads as on; the other four read as off; every
  case the UI switches over is reachable.
* **Bundle**: candidates include the lowercased name; a missing container returns `nil`
  rather than crashing.
* **Time zones**: the five default cities still resolve and still render times; every
  city has a localisation key.

## 8. Build and results

```
swift build : 0 errors, 0 warnings   (clean rebuild, .build removed)
swift test  : 264 tests, 0 failures
package     : build/Music HUD.app, 2 localisations in Contents/Resources
```

## 9. Snapshots

`docs/phase7-1/` — 12 images across both languages: `hud-en/zh`, `hud-min-en/zh`,
`hud-wide-en/zh`, `settings-general-en/zh`, `settings-status-en/zh`,
`settings-min-en/zh`.

## 10. Not verified / incomplete

1. **The `settings-*-en/zh` snapshots did not capture the Settings window.** They came
   out at HUD dimensions (488×696 / 940×1120 instead of ~1040×940), so
   `MUSICHUD_SNAPSHOT_SETTINGS=1` did not take effect in this run. The Settings UI is
   **not visually verified** in either language. This is a snapshot-harness problem, not
   a build problem, but it means I cannot claim the English Settings layout has been
   checked for overflow.
2. **HUD text is only partly localised.** Badges (`RECEIVING AUDIO`, `STARTING`,
   `IDLE`) and `TRACK` are intentionally identical in both languages, but the
   `来自 <artist>` prefix and some metadata labels are still Chinese-only.
3. **Language switching was not observed in the running app.** The mechanism is
   unit-tested and the tables are verified inside the built bundle, but I did not
   visually confirm the UI flipping between languages.
4. **Launch at Login was not toggled on the real system** — doing so would register a
   real login item. The status mapping is tested; the `SMAppService` round trip is not.
5. **No performance impact is claimed.** Localisation adds one bundle lookup per
   language change and nothing per frame; the audio thread, FFT, ring buffer,
   `SpectrumFrame`, `WindowDragMath` and `WindowDragModifier` were not touched.
