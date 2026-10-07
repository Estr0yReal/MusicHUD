# Music HUD

A translucent desktop music HUD for macOS: Apple Music now-playing info, a real-time
audio spectrum, and a retro digital display, combined into one small always-on-top
glass card that sits on your wallpaper.

> **Current status: Phase 7 — macOS native UX and product polish.** Version 1.0.0 (7).
> Menu-bar utility behaviour verified, permission states honest, window recovery
> verified end-to-end, and a bounded recovery for a stalled audio tap.
>
> **Phase 6 — information hierarchy + world clock.**
> Metadata hierarchy clarified, the transport row made legible, and the large
> display now has two modes: track time and a click-through world clock.
>
> **Phase 5 — reference matching and visual polish.**
> Everything from Phases 1–4.5 still works and is still verified: real Apple Music
> metadata, real Core Audio tap, real vDSP FFT. Phase 5 refined how it looks.
>
> **Phase 4 — real FFT spectrum, verified.**
> Metadata comes from Music.app over public Apple Events (Phase 2), real PCM comes
> from a public **Core Audio process tap** (Phase 3), and that PCM is now analysed
> with **Accelerate/vDSP** and drawn in the HUD's spectrum band (Phase 4).
> Every bar is a real FFT of real audio: there is no synthetic spectrum, no sine
> wave and no random data anywhere in the project.

![Music HUD](docs/snapshot-hud.png)

---

## What is and is not real

The brief asks for three states to be kept distinct, and mixing them up is the fastest
way to ship something that looks finished and is not.

| Capability | State |
|---|---|
| Borderless transparent floating window | **Implemented and verified** |
| Behind-window frosted glass, rounded corners, no window chrome | **Implemented and verified** |
| Drag to move, corner grip to resize | **Implemented and verified** |
| Retro seven-segment clock | **Implemented and verified** |
| Settings panel; every control changes real behaviour | **Implemented and verified** |
| Window level, opacity, click-through, position memory | **Implemented and verified** |
| Song title from Music.app | **Implemented and verified** |
| Artist / album / duration | **Implemented and verified** |
| Playback state (playing / paused / stopped) | **Implemented and verified** |
| Playhead position, with pause freezing it | **Implemented and verified** |
| Track-change detection (metadata + artwork) | **Implemented and verified** |
| Album artwork | **Implemented and verified** (1200×1200 JPEG) |
| Transport control (previous / play-pause / next) | **Implemented and verified** |
| Session elapsed time | **Implemented and verified** — real playback time, no longer a fake constant |
| Automation-permission handling + System Settings deep link | **Implemented and verified** |
| Real-time system audio capture (Core Audio process tap) | **Implemented and verified** |
| PCM → RMS / peak / dBFS | **Implemented and verified** |
| Standalone audio diagnostics panel | **Implemented and verified** |
| Pause, stop, track change, quit and relaunch handling | **Implemented and verified** |
| Real FFT spectrum (vDSP, 2048-point, 64 log bands) | **Implemented and verified** |
| Seven-segment digits with LCD ghost structure and a restrained glow | **Implemented and verified** |
| Accessibility labels on every control | **Implemented and verified** |
| Two-mode large display: track time + world clock | **Implemented and verified** |
| Click-to-cycle world clock (Track → Tokyo → Shanghai → London → New York → LA → Track) | **Implemented and verified** |
| World clock settings (enable / reorder / add / remove cities) | **Implemented and verified** |
| RMS / peak → dBFS with noise floor and attack/release smoothing | **Implemented and verified** |
| Spectrum decays to zero on pause/stop/quit | **Implemented and verified** |

**The `DEMO DATA` badge disappears when real data is flowing.** That is the visible
proof this phase did what it claims.

What is *not* shown as real:

* **Nothing at all in the spectrum.** Bar heights come from a real FFT of real PCM.
  The Phase 1 placeholder envelope was **deleted** in Phase 4 rather than left in the
  codebase, because a plausible-looking synthetic spectrum is exactly what the brief
  forbids.
* Demo mode still exists, but only as an explicitly selected development setting. It
  is never a fallback — when Apple Music is unavailable the card shows an idle state.
* There is no sine wave, no random buffer, no fixed fake level and no per-track
  heuristics anywhere in this project.

---

## Requirements

* macOS 14.0 or later (developed and verified on **macOS 15.5**, Apple Silicon)
* Xcode 16 or the matching Swift toolchain (verified with **Swift 6.1.2 / Xcode 16.4**)

No third-party dependencies.

---

## Build and run

```bash
./scripts/build-app.sh release
open "build/Music HUD.app"
```

Or for a development cycle: `swift build && swift run MusicHUD`

### Tests

```bash
./scripts/test.sh
```

**109 unit tests.** They run with no Music.app, no Automation permission and no Apple
Events: the provider is driven through the `MusicClient` seam by `MockMusicClient`, and
the Apple Event decoder is exercised against hand-built descriptors.

### A note on sandboxed build environments

`scripts/env.sh` redirects SwiftPM's caches and the Clang module cache into the project
directory and passes `--disable-sandbox`. Both are needed when building inside a
restricted shell — SwiftPM normally writes to `~/Library`, and it wraps manifest
compilation in its own `sandbox-exec`, which cannot nest. On a normal machine you can
ignore all of this and just run `swift build`.

---

## Using it

The app runs as an **accessory** (no Dock icon). Everything is reached from the
status-bar icon:

| Action | How |
|---|---|
| Move the card | Drag anywhere on it that is not a button |
| Resize | Drag the grip in the bottom-right corner |
| Play / pause / skip | The controls on the card — these really drive Music.app |
| Show / hide | Status-bar icon → 显示 HUD / 隐藏 HUD |
| Always on top | Status-bar icon → 窗口层级 → 始终置顶（浮层） |
| Click-through mode | Status-bar icon → 鼠标穿透模式 |
| Settings | Status-bar icon → 设置… |
| Quit | Status-bar icon → 退出 Music HUD |

---

## Permission

Music HUD reads Music.app over Apple Events, so macOS requires **Automation** access.

* The prompt appears the first time the app tries to read Music.app.
* Path: **System Settings → Privacy & Security → Automation → Music HUD → 音乐**.
* When access has been refused, the card says **"Music access required"** and the
  transport row becomes an **Open System Settings** button that deep-links to
  `x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`.
  That scheme and anchor are verified to be registered by System Settings on this
  system; if macOS ever moves the anchor, the call still opens System Settings, which
  is why the settings panel also spells out the manual path.
* `NSAppleEventsUsageDescription` in the bundle states exactly what is read and what is
  sent, and deliberately does **not** claim access to the user's library, because the
  code never modifies anything in it.

### Audio capture permission

Phase 3 needs a **second, different** permission, and it is worth being precise about
which one, because it is widely misreported:

| | |
|---|---|
| TCC service | **`kTCCServiceAudioCapture`** — shown in System Settings as **"System Audio Recording"** |
| Info.plist key | **`NSAudioCaptureUsageDescription`** |
| Screen Recording | **Not required** — and never requested |
| Microphone | **Not required** — and `NSMicrophoneUsageDescription` is deliberately absent |

Those facts were established from the system's own logs and string tables rather than
from memory:

* `tccd` logs `service="kTCCServiceAudioCapture"` for the audio request.
* `kTCCServiceScreenCapture` is never requested by this app.
* `NSAudioCaptureUsageDescription` was read out of `tccd`'s string table, not guessed.

Screen Recording and system audio capture are separate permissions, and conflating them
is a common mistake — including in this project's own history, where the Phase 1 bundle
shipped an unused `NSMicrophoneUsageDescription` "just in case". That key has been
**removed**; requesting permissions the app does not use is exactly what the brief
forbids.

**A bundle is required.** A bare Mach-O launched from a shell has no bundle identity, so
macOS attributes the request to the *responsible* process — typically the terminal — and
raises the prompt for that app instead. Launched from a shell, the tap call blocked for
**90 seconds** waiting on a permission decision that could never be answered for it. The
same code inside a signed `.app` bundle started in **0.00 s**. That is a packaging
problem masquerading as a code problem, and it is why `scripts/build-tools.sh` wraps the
probe in a real bundle.

Nothing here uses a private API. In particular **MediaRemote is not used** — it would
work, but it is a private framework and the brief rules it out. Note also that
`MPNowPlayingInfoCenter` cannot help: it reports only the *calling* app's own
now-playing session, so there is no public API to read another app's metadata that way.

---

## How the Music.app integration works

### Public AppleScript, verified against the installed app

Every property used was confirmed against the app's own scripting dictionary
(`sdef /System/Applications/Music.app`) rather than assumed:

* `player state` — enumeration `ePlS`: `stopped`, `playing`, `paused`,
  `fast forwarding`, `rewinding`
* `current track`, `player position`
* `track` → `name`, `artist`, `album`, `duration`, `persistent ID`
* `artwork` → `data` (a `picture`; Music.app reports `JPEG picture`)
* commands `playpause`, `next track`, `previous track`

### `NSAppleScript`, not `osascript`

Spawning an `osascript` process per poll would burn CPU, add latency and churn process
table entries. `NSAppleScript` runs in-process, and the script is **compiled once and
reused**, so a metadata poll costs well under a millisecond of scripting overhead after
the first call. Measured on this machine: **5 consecutive reads in 3 ms**.

`NSAppleScript` is not thread-safe, so all execution is confined to a single serial
queue. That also keeps a slow or hung Music.app from ever stalling the UI thread.

### One round trip, not nine

A single script returns all nine fields at once. Asking for title, artist, album,
duration, position, state and artwork separately would mean nine Apple Event round
trips per poll. Artwork is the one exception, and it is fetched only when the track
changes, because it is a separate 340 KB payload.

### Playhead interpolation, gated on transport state

`player position` is read once per poll (1.5 s by default). Fetching it more often would
mean an Apple Event per frame, so the displayed position is anchored to the last known
value and advanced locally — but **only while the transport is playing**:

| State | Behaviour |
|---|---|
| playing | advances |
| paused | frozen at the anchored value |
| stopped | frozen |
| new track | reset to the new anchor |

The estimator holds no clock of its own: callers pass `now`, which makes every one of
those behaviours directly unit testable. Small discrepancies between the local estimate
and a fresh reading are treated as jitter and ignored; a large one is treated as a seek
and re-anchors.

The fast 0.5 s display timer sends **no** Apple Events — it only re-renders from values
already in memory — and it is cancelled entirely while paused, so a paused HUD costs
nothing.

### Music.app is never launched as a side effect

`tell application "Music"` starts Music.app if it is not running. Two guards prevent
that:

* `NSRunningApplication.runningApplications(withBundleIdentifier:)` is checked first —
  public AppKit, no Apple Event, no launch.
* Verified on macOS 15.5 that `application "Music" is running` does **not** launch the
  app, so the same check is repeated inside the script to close the race where Music.app
  quits between the two.

Pressing a transport button when Music.app is not running does nothing at all.

---

## How audio capture works

**Backend: Core Audio process tap.** Chosen over ScreenCaptureKit and over a virtual
audio device because it lets the HUD tap *Music.app specifically* — capturing the whole
system output would put Chrome, Discord, notification sounds and games into the
spectrum, which is not what this component is for.

```
Music.app
  → Core Audio process object      (kAudioHardwarePropertyTranslatePIDToProcessObject)
  → CATapDescription(stereoMixdownOfProcesses:)
  → AudioHardwareCreateProcessTap  (macOS 14.2+)
  → private aggregate device carrying the tap
  → AudioDeviceCreateIOProcIDWithBlock
  → AudioBufferList  →  RMS / peak  →  diagnostics panel
```

Every symbol above was read out of the macOS 15.5 SDK headers and then exercised on
real audio, rather than assumed. The app never launches Music.app as a side effect, and
a tap is torn down and rebuilt when Music.app quits and comes back.

### What the tap actually delivers

Measured on this machine, playing Apple Music:

| Property | Value |
|---|---|
| Sample rate | **48000 Hz** |
| Channels | **2** |
| Format | `lpcm`, Float32, **interleaved** |
| Bytes per frame | 8 |
| Buffer size | 512 frames per callback (~94 callbacks/s) |
| Measured throughput | ~47600 frames/s |

### Real measured levels

| Source state | RMS | Peak |
|---|---|---|
| Playing, quiet passage | −41.3 dBFS | −31.2 dBFS |
| Playing, loud passage | −29.5 dBFS | −18.5 dBFS |
| Paused mid-track | **−120.0 dBFS (floor)** | **−120.0 dBFS (floor)** |
| Music.app stopped | −120.0 dBFS | −120.0 dBFS |

The paused and stopped rows are the important ones: the callbacks keep arriving at the
full ~94/s with an all-zero payload, and the panel reports `SILENT` — not "broken".

### Channel handling

All channels are combined: the sum of squares is accumulated across every channel and
the RMS is divided by the total sample count. Correlated stereo — the normal case for
music — gives the same reading as either channel alone, and energy panned hard to one
side can never be missed. The consequence, documented and unit tested, is that a
hard-panned signal reads about 3 dB lower than the active channel alone, because the
silent channel is included in the average.

### Real-time safety

The IOProc does no allocation, no logging, no ObjC, no I/O and no UI work. It folds
samples into a `LevelAccumulator` behind a short `os_unfair_lock` and bumps two
counters. A 20 Hz main-thread timer drains that and publishes; the audio thread never
touches an `@Published` property. Diagnostic output is one line per second, never per
callback.

### The state machine

`idle` · `starting` · `receiving` · `silent` · `permissionDenied` · `unsupported` ·
`failed` · `stopped`.

`AudioCaptureResult` keeps `.noData` and `.silence` strictly apart, because live
measurement proved they are genuinely different conditions:

* Music.app **idle** → the tap produces **no callbacks at all** → `noData` → `idle`.
* Music.app **paused mid-track** → callbacks keep arriving, payload all zeros →
  `silence` → `silent`.

Treating those as one "not working" state would be wrong in both directions.

`unsupported` covers macOS 14.0–14.1, where the process-tap API does not exist. The
package still deploys to 14.0; only the capture path is gated to 14.2+.

## How the spectrum works

```
Music.app
  → Core Audio process tap              (Phase 3, verified)
  → mono PCM  (L+R)/2
  → AudioRingBuffer                     (audio thread: write and return)
  → Hann window                         (reduces spectral leakage)
  → vDSP real FFT, 2048-point           (Accelerate)
  → magnitude                           (vDSP_zvmags, sqrt)
  → amplitude normalisation             (window coherent gain + vDSP's 2x factor)
  → dBFS                                (20·log10)
  → 48 log-spaced bands, 20 Hz … 20 kHz
  → noise floor + dynamic range         (map to 0…1)
  → asymmetric attack / release         (smoothing)
  → SpectrumFrame                       (the only thing the renderer sees)
  → SpectrumView                        (a Canvas, nothing more)
```

### Threading

| Stage | Thread |
|---|---|
| Mix to mono, push to ring buffer | **audio thread** — no FFT, no allocation, no logging |
| Window, FFT, bands, smoothing | **analysis queue** (serial, userInitiated) |
| Publish the newest frame | **main actor** |
| Draw | **SwiftUI**, reading the newest frame |

The ~94 Hz FFT rate never becomes a ~94 Hz UI rate: the analysis runs on its own
queue and SwiftUI re-renders from whatever frame is current. The audio callback
measured **well under 1 ms** against a 10.67 ms budget.

### Two SDK details that had to be checked, not assumed

* **`vDSP_fft_zrip` applies a forward `scale = 2`.** Its output is twice the true DFT.
  Without dividing that out every reading would be +6 dB too hot. A bin-centred
  0.5-amplitude sine now recovers exactly 0.5 — asserted by a test.
* **`vDSP_hann_window` needs `vDSP_HANN_DENORM`,** otherwise it multiplies by
  `0.8165`; and its formula uses `N` rather than the `N−1` the brief specifies. The
  window is therefore computed directly from the brief's formula, once, at
  construction.

The amplitude normalisation divides by `sum(window)`, so 1024-, 2048- and 4096-point
FFTs all report the same level for the same audio — also asserted by a test.

### Band mapping

48 bands from 20 Hz to 20 kHz in a geometric progression, each aggregated as the RMS
of its bins rather than the maximum, because a single bin peak jitters frame to frame
and reads as noise. Below roughly 100 Hz a band is *narrower* than one FFT bin, so a
low tone's energy legitimately splits across two adjacent bands; this is documented
and covered by a test rather than tuned away.

### Frame-rate independent smoothing

Attack and release are defined as time constants and converted to a per-tick
coefficient from the real elapsed time, so the spectrum looks identical at 20, 30 and
60 FPS. Release alone is user-adjustable; attack stays fast so drum transients are
not softened.

## Requirements and permissions

| | |
|---|---|
| macOS | 14.0 or later (built and verified on **15.5**) |
| Music.app | **required** for metadata and transport; the HUD never launches it |
| System Audio Recording | required for the spectrum — `NSAudioCaptureUsageDescription` |
| Automation (Apple Events) | required for metadata and transport — `NSAppleEventsUsageDescription` |
| Microphone | **never requested, never used** |
| Screen Recording | **never requested, never used** |

Only two usage-description keys exist in the built `Info.plist`; this is verifiable with
`plutil -p "build/Music HUD.app/Contents/Info.plist"`.

### Menu-bar utility behaviour

The app runs as an accessory: no Dock icon, no main menu bar, one status item.

```
显示 HUD / 隐藏 HUD
窗口层级 · 鼠标穿透模式 · 重置窗口位置
设置… ⌘,     音频诊断… ⌘D
版本 <version>              ← read from Info.plist, never hardcoded
退出 Music HUD ⌘Q
```

Hiding the HUD does **not** quit the app and does not stop audio analysis. Quit is
`NSApp.terminate`.

### Window recovery

The saved position is restored whenever it still intersects a screen. If it does not —
for example the display it was on has gone away — the window is moved to a safe position
on the current screen **without changing its size**. A window pushed to a screen edge is
never snapped back or recentred.

### Audio capture recovery

A process tap can occasionally register with coreaudiod and then deliver nothing, even
while the source is playing. This is an OS-side condition, not a permission problem.
After a started tap has produced no audio for 8 s the app rebuilds it, up to three
times, then reports the condition rather than retrying for ever. A tap that has ever
delivered audio is never rebuilt, so a quiet passage cannot tear down a working capture.

## Phase 5 — visual polish

Reference audit and per-item results: `docs/phase5-reference-audit.md`.
Snapshot set: `docs/phase5/`.

### What changed

| Area | Change | Why |
|---|---|---|
| Seven-segment ghosts | Stroke weight 0.16 → **0.095**, alpha 0.06 → **0.045** | Seven lit-weight strokes with round caps union into a filled rounded rectangle, so every digit sat on a dark plate instead of showing unlit segment structure |
| Seven-segment glow | Added a blurred halo under the lit strokes | The reference digits read as emissive components, not printed shapes |
| Spectrum bands | 48 → **64** | Measured: 64 costs the same as 48 (medians 7.75/8.00% vs 8.75/7.50% — within noise), and matches the reference's finer, denser bars. 72 cost 8.75% and read as a picket fence |
| Transport / resize accessibility | `accessibilityLabel` and hints added | VoiceOver previously saw only SF Symbol names |

### What deliberately did **not** change

Window behaviour, overall proportions (already within ~1 % of the reference on every
ratio), artwork, typography, spacing, alignment, background material, border weight,
shadows, the FFT pipeline, the tap, metadata handling and permissions. A change with no
clear visual gain was rejected, as were any that would trade visual quality for CPU.

### Snapshot-only instrumentation

Three environment variables exist purely to make the required layout snapshots
reachable. They are inert in normal use:

| Variable | Purpose |
|---|---|
| `MUSICHUD_SNAPSHOT_TITLE` / `_ARTIST` / `_ALBUM` | Renders a given title so the long / CJK layout cases can be captured — a real Music.app library cannot produce those on demand |
| `MUSICHUD_SNAPSHOT_WINDOW_SIZE=WxH` | Renders at minimum / maximum size |
| `MUSICHUD_SNAPSHOT_ON_AUDIO=1` | Captures only once real FFT data is flowing |

They replace **display text only** and cannot affect audio, FFT or transport.

## Phase 6 — information hierarchy + world clock

### The two display modes

| Mode | Digits | Caption |
|---|---|---|
| **Track** | whatever `ClockMode` is configured (elapsed / progress / local time) | `TRACK` |
| **World clock** | that city's wall-clock time | `TOKYO · JST` |

Clicking the large display advances the rotation: Track → Tokyo → Shanghai →
London → New York → Los Angeles → Track. Disabled cities are skipped, and Settings can
enable, reorder, add and remove them. The interaction is a plain tap with no
transition animation.

### Time zones, and one SDK limitation worth recording

All conversion goes through `TimeZone`; **no UTC offset is computed by this project**,
and DST comes from the system database via `isDaylightSavingTime(for:)`.

Abbreviations were verified on macOS 15.5 rather than assumed, and the result is not
what the obvious API suggests:

| City | `TimeZone.localizedName` returns | Shown |
|---|---|---|
| New York | `EST` / `EDT` | system value |
| Los Angeles | `PST` / `PDT` | system value |
| **Tokyo** | `GMT+9` | `JST` (curated) |
| **Shanghai** | `GMT+8` | `CST` (curated; no DST) |
| **London** | `GMT` / `GMT+1` | `GMT` / `BST` (curated) |

`TimeZone.abbreviation(for:)` and `localizedName(for:locale:)` both fall back to a bare
`GMT±N` for zones ICU has no short name for, so the brief's `JST` and `BST` are not
obtainable from them. The app therefore uses the **system value whenever it carries
identity**, and a small curated label only when the system returned a bare offset.
DST selection is always the system's.


### Adding a city to a stored configuration

`WorldClockStore` keeps a schema marker (`MusicHUD.worldClock.schema`) alongside the
city list. When Shanghai was introduced, existing configurations were **migrated
insertively**: the new city is placed where it belongs in the rotation (after Tokyo)
and every existing entry keeps its position and its enabled/disabled state. The marker
means the migration runs once — a user who deliberately deletes a city keeps it
deleted rather than finding it resurrected on the next launch.

### Layout changes

| Area | Change |
|---|---|
| Track title | 11.5 pt semibold → **13 pt bold**, opacity 0.95 → 0.98 |
| Artist line | grey 0.46 → **0.62** (medium emphasis) |
| Album / source rows | 9.8 → **9.2 pt**, value opacity 0.68 → 0.50, labels 0.34 → 0.30 |
| Metadata separator | opacity 0.10 → **0.13**, with an **8 pt horizontal inset** so it divides the metadata block rather than spanning the card |
| Previous / Next | `Previous` → **`PREVIOUS`** with 1.0 pt tracking, weight regular → medium, opacity 0.42 → 0.54, larger arrows, and a hit target of 82 × 30 pt with no visual change |

The hierarchy comes from the **gap** between levels, not from raising everything.

## Architecture

```
MusicTimerWigdet/
├── Package.swift
├── Sources/
│   ├── MusicHUDCore/                 # Pure logic. No AppKit, no SwiftUI. Unit tested.
│   │   ├── AppleMusic/
│   │   │   ├── TrackMetadata.swift        # TrackMetadata, PlaybackState, NowPlayingSnapshot
│   │   │   ├── NowPlayingProviding.swift  # Provider protocol + MockNowPlayingService + DemoLibrary
│   │   │   ├── MusicClient.swift          # The narrow seam to Music.app + error mapping
│   │   │   ├── MusicAvailability.swift    # The three distinct failure states
│   │   │   ├── AppleEventDecoding.swift   # Descriptor → model, where the subtle bugs live
│   │   │   ├── AppleMusicNowPlayingService.swift  # Polling, track changes, artwork
│   │   │   ├── PositionEstimator.swift    # Transport-gated playhead interpolation
│   │   │   ├── SessionClock.swift         # Real playback-time accumulation
│   │   │   ├── ArtworkCache.swift         # LRU cover cache
│   │   │   └── MockMusicClient.swift      # Test double: no Music.app required
│   │   ├── Audio/
│   │   │   ├── AudioAnalysis.swift        # The audio → renderer contract (Phase 4)
│   │   │   ├── AudioLevel.swift           # AudioLevel, AudioCaptureState, AudioCaptureResult
│   │   │   ├── AudioLevelCalculator.swift # PCM → RMS / peak, and dBFS
│   │   │   └── AudioCaptureSource.swift   # Music.app process vs whole system
│   │   ├── Rendering/                     # HUDMetrics, SevenSegment, formatters, palettes
│   │   └── Settings/                      # HUDSettings + store + sanitisation
│   └── MusicHUD/                     # The application.
│       ├── main.swift
│       ├── App/                      # AppDelegate, AppState, ViewSnapshotter, StateTracer
│       ├── AppleMusic/AppleScriptMusicClient.swift   # The only file that sends Apple Events
│       ├── Audio/
│       │   ├── CoreAudioTapCapture.swift  # The only file that touches Core Audio taps
│       │   └── AudioCaptureService.swift  # State machine, retry policy, diagnostics log
│       ├── Window/                   # Panel, controller, levels, blur
│       └── UI/                       # All SwiftUI views + AudioDiagnosticsView
├── Tests/MusicHUDCoreTests/
├── tools/AudioCaptureProbe.swift     # Standalone Phase 3 verification probe
└── scripts/                          # env, build-app, build-tools, test, snapshot
```

Separation of concerns worth calling out:

* **`AppleScriptMusicClient` is the only file that talks to Music.app.** Everything
  else sees `MusicClient`, which has four methods.
* **`AppState` is the composition root.** The scripting client lives in the app target
  and the provider lives in the logic target; they are paired up in exactly one place,
  which is what lets the whole provider be tested against a mock.
* **No view ever calls AppleScript.** Views read `AppState` and nothing else.
* **The logic target imports no UI framework**, which is what makes it testable.

---

## Verifying the appearance and the behaviour

### `scripts/snapshot.sh` — rendering without Screen Recording permission

```bash
./scripts/snapshot.sh            # writes .build-cache/shots/hud.png
```

**Do not trust `screencapture` here.** During Phase 1 the HUD appeared completely
invisible: the window was in the window server's on-screen list at the right position
and size, with the process healthy and idle, but the screenshot showed only wallpaper
and menu bar. The cause was not a rendering bug — without Screen Recording permission
macOS silently omits *every other process's windows* from a capture, while the desktop
picture and menu bar still render. `ViewSnapshotter` renders the view hierarchy from
inside the process instead, needs no permission, and cannot lie.

### `StateTracer` — proving behaviour over time

```bash
MUSICHUD_TRACE=/tmp/trace.txt MUSICHUD_TRACE_DURATION=30 \
  "build/Music HUD.app/Contents/MacOS/MusicHUD"
```

A screenshot proves what the card looked like at one instant. It cannot show that the
playhead *stopped* when the music was paused. The tracer samples the live state once a
second so those behaviours can be verified rather than assumed — and it is how the
playhead bug below was found.

Other development variables:

```bash
MUSICHUD_SNAPSHOT=/tmp/hud.png \
MUSICHUD_SNAPSHOT_SETTINGS=/tmp/settings.png \
MUSICHUD_SNAPSHOT_TAB=music \
  "build/Music HUD.app/Contents/MacOS/MusicHUD"
```

---

## Bugs that only live verification found

Recorded because both were invisible to the unit tests as originally written, and both
would have shipped looking plausible.

**1. AppleScript returns booleans as `'true'`, not `'bool'`.**
The decoder checked for descriptor type `'bool'` — which is the obvious assumption, and
is even what Apple's own constant is called. But a script returning `true` produces a
null descriptor typed `'true'` (0x74727565), so `hasTrack` read back as `false` every
single time. The card showed "No music playing" while title, state and position were all
being read perfectly, which made it look like anything but a decoding problem.
`AppleEventDecoding` now handles all three forms and has regression tests.

**2. The playback tick overwrote the position with an unanchored zero.**
When a reading was not displayable the estimator was reset, and the 0.5 s tick then
published `estimate() == 0` over a valid value. The trace showed the position
alternating `38.83 → 0.00 → 40.05`. Since 0 is a perfectly plausible playhead position,
the corruption was silent. The tick is now guarded on the estimator being anchored.

**3. The tap rebuild path was a busy loop.**
When Music.app quit and came back, the recovery logic ran on the 20 Hz meter timer.
Music.app exposes its Core Audio process object a moment *after* the process appears, so
the first rebuild attempt failed — and the retry fired again 50 ms later, tearing down
and rebuilding taps twenty times a second. A live log showed two attempts inside 0.1 s.
There are now one decision point and a 1.5 s minimum interval between attempts.

**4. The spectrum drew correctly while the state machine thought nothing was
playing.** `CoreAudioTapCapture` created its *own* `TapCallbackCounter`, while the
service drained a different instance that never received anything. The engine was
shared, so the FFT worked and the bars were real — but `state` stayed on `STARTING`
and the log repeated "no active PCM". Two contradictory symptoms from one mistake.

**5. `onDeviceStarted` was assigned after `start()`.** `start()` dispatches the device
start asynchronously and captured the closure at that moment, so assigning it
afterwards meant it never fired, `deviceStarted` stayed false, and the watchdog
falsely reported "audio capture permission is not granted" while audio was flowing
perfectly.

**6. The supervisor's tap retry could fire while setup was still in flight.** Since
setup became asynchronous, `capture` stayed nil for a while and the 1 Hz supervisor
built a second tap two seconds later, discarding the first. A generation counter and
an `isSettingUpTap` flag now make it single-flight.

**7. `Frames / s` reported samples, not frames.** Interleaved stereo has two samples
per frame, so a 48 kHz stream read as 96 kHz in the diagnostics panel. Now divided by
`mBytesPerFrame`.

**8. The playback tick overwrote the position with an unanchored zero (Phase 2).**
Music.app frequently has no cover yet for a track that has only just started streaming.
Recording the first `nil` as a fact meant never noticing when the cover arrived. Only
successful reads are cached now, and a missing cover is retried for a few polls.

---

## Known limitations

**What public AppleScript cannot give us**

* **Only the first artwork.** `data of artwork 1` is read; a track with several covers
  yields one.
* **No audio stream.** Metadata is not audio. Real-time PCM is Phase 3 and is a separate
  problem entirely.
* **`player position` precision** is what Music.app reports (roughly 0.1 s), which is
  why the display interpolates.
* **`missing value` is legitimate** for fields like `artist` on some media kinds. Those
  read as empty strings rather than failing the whole poll — covered by a test.
* **Radio and live streams** have no meaningful duration, so the progress bar has
  nothing to show. The playhead still advances.
* **Music.app must already be running.** We deliberately never launch it.
* Nothing in the scripting dictionary exposes DRM or stream-quality state, and the
  `lyrics` property is deliberately not read (large, slow, and not needed).

**Audio capture**

* **Only macOS 14.2 and later** can do process taps. On 14.0–14.1 the app reports
  `unsupported` rather than failing.
* **A tap reports no callbacks while the source is idle.** Music.app that is running but
  not playing produces nothing at all, so "silence" and "no data" must be read as
  different signals — which is why the state machine keeps them apart.
* **The tap follows the process, not the track.** When Music.app quits, the process
  object disappears and the tap is torn down; it is rebuilt when the app returns.
* **`AudioDeviceStart` blocks while the permission prompt is unanswered** — around 90 s
  in the worst case. It is therefore dispatched off the main thread and given an 8 s
  budget, after which the panel reports `permissionDenied` rather than appearing hung.
* **The diagnostics panel is a tool, not the product UI.** It is opened from the
  status-bar menu, capture runs only while it is open, and it is not connected to the
  HUD in any way.
* Frame counts in the panel are for the most recent ~50 ms sample window; the
  `Frames / s` row is a separately measured rate, not that number multiplied by 20.

**Spectrum**

* **CPU is dominated by UI presentation, not by the DSP.** The FFT costs ~0.03–0.07 ms
  per tick (roughly 0.2% CPU). Presenting a frame costs a full UI update of a
  vibrancy-backed window, measured at **~15% CPU at 60 FPS, ~8% at 30 FPS, ~5% at
  20 FPS**. The default is therefore **30 FPS**, which is smooth for a bar meter this
  size; 60 FPS remains selectable. The DSP itself is never the bottleneck.
* **Below ~100 Hz a band is narrower than one FFT bin**, so a low tone's energy splits
  across adjacent bands and neither recovers full amplitude. A consequence of the
  chosen log mapping at this FFT size, documented and tested rather than hidden.
* **The tap must be started while the source is actually producing audio.**
  `AudioHardwareCreateProcessTap` and aggregate-device creation can block for tens of
  seconds while coreaudiod waits for its IO context — the system log shows
  "Starting tap after waiting for writers", observed at 23.9 s and 36.7 s in different
  runs. Tap setup therefore runs off the main thread so the HUD never freezes; the
  card shows `STARTING` meanwhile.
* **No stereo spectrum.** Channels are summed to mono, as the brief specifies.

**Other**
* The **desktop-layer window mode** is experimental: it uses the public
  `CGWindowLevelForKey(.desktopWindow)`, which puts the card above the wallpaper and
  below the desktop icons, but the Finder's desktop window sits above it, so it may not
  receive clicks. The floating level is the reliable choice and the default.
* **Borderless resize is driven by a custom grip**, because AppKit does not reliably
  give borderless windows native edge-drag resizing.

---

## Roadmap

### Phase 3 — Real system audio capture ✅ delivered

Verified. See "How audio capture works" above. The standalone probe in
`tools/AudioCaptureProbe.swift` remains useful for re-checking the pipeline in
isolation from the app.

### Phase 4 — FFT spectrum ✅ delivered

Verified. See "How the spectrum works" above. Phase 1's placeholder envelope was
deleted: with real data available, leaving a synthetic fallback in the codebase would
have been a standing invitation to draw fake bars.

### Phases 5–8 — Polish, release

Session/progress polish, keyboard shortcuts, error states, performance work, signing
and notarisation.

---

## Licence

Not yet chosen.
