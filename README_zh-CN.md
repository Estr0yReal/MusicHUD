<div align="center">

# Music HUD

一款轻量级的 macOS 音乐 HUD：Apple Music 当前播放信息、实时音频频谱，以及复古数字显示，全部组合在一张悬浮于桌面壁纸之上的半透明玻璃卡片里。

[🇺🇸 English README](README.md) | **🇨🇳 中文 README**

</div>

![Music HUD](docs/snapshot-hud.png)

---

## 环境要求

* macOS 14.0 或更新版本（在 **macOS 15.5**、Apple Silicon 上开发并验证）
* Xcode 16 或匹配的 Swift 工具链（使用 **Swift 6.1.2 / Xcode 16.4** 验证）
* 不需要其他的任何第三方依赖。

---

## 构建与运行

```bash
./scripts/build-app.sh release
open "build/Music HUD.app"
```

开发循环则用：`swift build && swift run MusicHUD`

---

## 使用方法

应用以 **accessory** 模式运行（没有 Dock 图标）。所有功能都通过状态栏图标进入：

| 操作 | 方式 |
|---|---|
| 移动卡片 | 拖动卡片上任意非按钮区域 |
| 调整大小 | 拖动右下角的握柄 |
| 播放 / 暂停 / 切歌 | 卡片上的控件 |
| 显示 / 隐藏 | 状态栏图标 → 显示 HUD / 隐藏 HUD |
| 窗口置顶 | 状态栏图标 → 窗口层级 → 始终置顶（浮层） |
| 鼠标穿透模式 | 状态栏图标 → 鼠标穿透模式 |
| 设置 | 状态栏图标 → 设置… |
| 退出 | 状态栏图标 → 退出 Music HUD |

---

## 权限

Music HUD 通过 Apple Events 读取 Music.app，因此 macOS 要求**自动化**权限。

* 首次尝试读取 Music.app 时会弹出授权提示。
* 路径：**系统设置 → 隐私与安全性 → 自动化 → Music HUD → 音乐**。
* 当访问被拒绝时，卡片会显示 **"Music access required"**，传输控件行会变成一个 **Open System Settings** 按钮，深链到
  `x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`。
  该 scheme 与锚点已验证在本系统上由「系统设置」注册；即便 macOS 将来移动了锚点，该调用仍会打开系统设置——这正是设置面板同时写明手动路径的原因。
* Bundle 中的 `NSAppleEventsUsageDescription` 精确说明了读取什么、发送什么，并且**刻意不**声称可以访问用户的音乐资料库。

### 音频采集权限

需要**第二个、不同的**权限，这里值得说清楚是哪一个，因为它经常被误报：

| | |
|---|---|
| TCC 服务 | **`kTCCServiceAudioCapture`** —— 在系统设置中显示为 **"系统音频录制"** |
| Info.plist 键 | **`NSAudioCaptureUsageDescription`** |
| 屏幕录制 | **不需要** —— 也从未申请 |
| 麦克风 | **不需要** —— 且 `NSMicrophoneUsageDescription` 被刻意移除 |

### 菜单栏常驻行为

应用以 accessory 模式运行：没有 Dock 图标，没有主菜单栏，只有一个状态栏项。

```
显示 HUD / 隐藏 HUD
窗口层级 · 鼠标穿透模式 · 重置窗口位置
设置… ⌘,     音频诊断… ⌘D
版本 <version>              ← 从 Info.plist 读取，绝不硬编码
退出 Music HUD ⌘Q
```



## 信息层级 + 世界时钟

### 两种显示模式

| 模式 | 数字 | 副标题 |
|---|---|---|
| **Track** | `ClockMode` 配置的内容（累计 / 进度 / 本地时间） | `TRACK` |
| **世界时钟** | 该城市的墙上时钟时间 | `TOKYO · JST` |

点击大号显示会推进轮换：Track → 东京 → 上海 → 伦敦 → 纽约 → 洛杉矶 → Track。被禁用的城市会被跳过，设置中可以启用、排序、添加和删除它们。交互就是一次普通点按，没有任何过渡动画。

### 时区，以及一个值得记录的 SDK 限制

所有换算都经由 `TimeZone`；**本项目不计算任何 UTC 偏移**，夏令时来自系统数据库的 `isDaylightSavingTime(for:)`。

缩写是在 macOS 15.5 上实测的，而不是假设的，结果与最显而易见的 API 所暗示的并不一致：

| 城市 | `TimeZone.localizedName` 返回 | 实际显示 |
|---|---|---|
| New York | `EST` / `EDT` | 系统值 |
| Los Angeles | `PST` / `PDT` | 系统值 |
| **Tokyo** | `GMT+9` | `JST`（人工整理） |
| **Shanghai** | `GMT+8` | `CST`（人工整理；无夏令时） |
| **London** | `GMT` / `GMT+1` | `GMT` / `BST`（人工整理） |



## 架构

```
MusicTimerWigdet/
├── Package.swift
├── Sources/
│   ├── MusicHUDCore/                 # 纯逻辑。无 AppKit、无 SwiftUI。有单元测试。
│   │   ├── AppleMusic/
│   │   │   ├── TrackMetadata.swift        # TrackMetadata, PlaybackState, NowPlayingSnapshot
│   │   │   ├── NowPlayingProviding.swift  # Provider protocol + MockNowPlayingService + DemoLibrary
│   │   │   ├── MusicClient.swift          # 通向 Music.app 的窄接缝 + 错误映射
│   │   │   ├── MusicAvailability.swift    # 三种不同的失败状态
│   │   │   ├── AppleEventDecoding.swift   # Descriptor → model，微妙 bug 的藏身处
│   │   │   ├── AppleMusicNowPlayingService.swift  # 轮询、切歌、封面
│   │   │   ├── PositionEstimator.swift    # 受传输状态门控的播放头插值
│   │   │   ├── SessionClock.swift         # 真实播放时长累计
│   │   │   ├── ArtworkCache.swift         # LRU 封面缓存
│   │   │   └── MockMusicClient.swift      # 测试替身：不需要 Music.app
│   │   ├── Audio/
│   │   │   ├── AudioAnalysis.swift        # 音频 → 渲染器的契约（Phase 4）
│   │   │   ├── AudioLevel.swift           # AudioLevel, AudioCaptureState, AudioCaptureResult
│   │   │   ├── AudioLevelCalculator.swift # PCM → RMS / peak，以及 dBFS
│   │   │   └── AudioCaptureSource.swift   # Music.app 进程 vs 整个系统
│   │   ├── Rendering/                     # HUDMetrics, SevenSegment, formatters, palettes
│   │   └── Settings/                      # HUDSettings + store + sanitisation
│   └── MusicHUD/                     # 应用本体。
│       ├── main.swift
│       ├── App/                      # AppDelegate, AppState, ViewSnapshotter, StateTracer
│       ├── AppleMusic/AppleScriptMusicClient.swift   # 唯一发送 Apple Events 的文件
│       ├── Audio/
│       │   ├── CoreAudioTapCapture.swift  # 唯一触碰 Core Audio tap 的文件
│       │   └── AudioCaptureService.swift  # 状态机、重试策略、诊断日志
│       ├── Window/                   # Panel, controller, levels, blur
│       └── UI/                       # 全部 SwiftUI 视图 + AudioDiagnosticsView
├── Tests/MusicHUDCoreTests/
├── tools/AudioCaptureProbe.swift     # 独立的 Phase 3 验证探针
└── scripts/                          # env, build-app, build-tools, test, snapshot
```

