<div align="center">

# Music HUD

一款轻量级的 macOS 音乐 HUD：Apple Music 当前播放信息、实时音频频谱，以及复古数字显示，全部组合在一张悬浮于桌面壁纸之上的半透明玻璃卡片里。

[🇺🇸 English README](README.md) | **🇨🇳 中文 README**

</div>

> **当前状态：Phase 7 —— macOS 原生体验与产品打磨。** 版本 1.0.0 (7)。
> 菜单栏常驻行为已验证，权限状态如实上报，窗口恢复已端到端验证，音频 tap 卡死时具备有界恢复。
>
> **Phase 6 —— 信息层级 + 世界时钟。**
> 元数据层级梳理清楚，传输控件行变得可读，大号显示现在有两种模式：曲目时间与点击切换的世界时钟。
>
> **Phase 5 —— 参考图对齐与视觉打磨。**
> Phase 1–4.5 的一切仍然正常工作且仍然经过验证：真实的 Apple Music 元数据、真实的 Core Audio tap、真实的 vDSP FFT。Phase 5 打磨的是它的外观。
>
> **Phase 4 —— 真实 FFT 频谱，已验证。**
> 元数据通过公开的 Apple Events 从 Music.app 读取（Phase 2），真实 PCM 来自公开的 **Core Audio process tap**（Phase 3），这些 PCM 现在经由 **Accelerate/vDSP** 分析并绘制在 HUD 的频谱带中（Phase 4）。
> 每一根柱子都是真实音频的真实 FFT：整个项目中没有任何合成频谱、没有正弦波、没有随机数据。

![Music HUD](docs/snapshot-hud.png)

---

## 哪些是真的，哪些不是

本项目要求把三种状态严格区分开——把它们混为一谈，是交出"看起来完成了、其实没有"的东西最快的途径。

| 能力 | 状态 |
|---|---|
| 无边框透明悬浮窗口 | **已实现并验证** |
| 窗口背后磨砂玻璃、圆角、无窗口装饰 | **已实现并验证** |
| 拖动移动、右下角握柄缩放 | **已实现并验证** |
| 复古七段数码管时钟 | **已实现并验证** |
| 设置面板；每个控件都改变真实行为 | **已实现并验证** |
| 窗口层级、透明度、鼠标穿透、位置记忆 | **已实现并验证** |
| 来自 Music.app 的歌曲标题 | **已实现并验证** |
| 艺术家 / 专辑 / 时长 | **已实现并验证** |
| 播放状态（播放中 / 已暂停 / 已停止） | **已实现并验证** |
| 播放进度，暂停时冻结 | **已实现并验证** |
| 切歌检测（元数据 + 封面） | **已实现并验证** |
| 专辑封面 | **已实现并验证**（1200×1200 JPEG） |
| 传输控制（上一首 / 播放暂停 / 下一首） | **已实现并验证** |
| 本次播放累计时长 | **已实现并验证** —— 真实播放时间，不再是假常量 |
| 自动化权限处理 + 系统设置深链 | **已实现并验证** |
| 实时系统音频采集（Core Audio process tap） | **已实现并验证** |
| PCM → RMS / peak / dBFS | **已实现并验证** |
| 独立的音频诊断面板 | **已实现并验证** |
| 暂停、停止、切歌、退出与重启的处理 | **已实现并验证** |
| 真实 FFT 频谱（vDSP，2048 点，64 个对数频段） | **已实现并验证** |
| 带 LCD 幽灵段结构与克制辉光的七段数码管 | **已实现并验证** |
| 每个控件的无障碍标签 | **已实现并验证** |
| 双模式大号显示：曲目时间 + 世界时钟 | **已实现并验证** |
| 点击循环世界时钟（Track → 东京 → 上海 → 伦敦 → 纽约 → 洛杉矶 → Track） | **已实现并验证** |
| 世界时钟设置（启用 / 排序 / 添加 / 删除城市） | **已实现并验证** |
| RMS / peak → dBFS，含噪声门限与 attack/release 平滑 | **已实现并验证** |
| 暂停 / 停止 / 退出时频谱衰减到零 | **已实现并验证** |

**真实数据开始流动时，`DEMO DATA` 角标会消失。** 这就是本阶段做到了它所声称之事的可见证据。

以下内容**没有**被当作真实数据展示：

* **频谱里什么都没有。** 柱高来自真实 PCM 的真实 FFT。Phase 1 的占位包络在 Phase 4 被**删除**了，而不是留在代码库里——一个看起来合理的合成频谱，正是本项目明令禁止的东西。
* 演示模式仍然存在，但只是一个需要显式选择的开发用设置。它**从不用作降级方案**——当 Apple Music 不可用时，卡片会显示空闲状态。
* 整个项目里没有正弦波、没有随机缓冲、没有固定的假电平，也没有任何针对单曲的启发式规则。

---

## 环境要求

* macOS 14.0 或更新版本（在 **macOS 15.5**、Apple Silicon 上开发并验证）
* Xcode 16 或匹配的 Swift 工具链（使用 **Swift 6.1.2 / Xcode 16.4** 验证）

无任何第三方依赖。

---

## 构建与运行

```bash
./scripts/build-app.sh release
open "build/Music HUD.app"
```

开发循环则用：`swift build && swift run MusicHUD`

### 测试

```bash
./scripts/test.sh
```

**264 个单元测试。** 它们不需要 Music.app、不需要自动化权限、也不需要 Apple Events：provider 通过 `MusicClient` 这个接缝由 `MockMusicClient` 驱动，Apple Event 解码器则用手工构造的 descriptor 来测试。

### 关于沙箱构建环境

`scripts/env.sh` 会把 SwiftPM 的缓存和 Clang module 缓存重定向到项目目录，并传入 `--disable-sandbox`。在受限的 shell 里构建时两者都是必需的——SwiftPM 通常会写入 `~/Library`，而且它会用自己的 `sandbox-exec` 包裹 manifest 编译，而沙箱无法嵌套。在普通机器上你完全可以忽略这些，直接 `swift build` 即可。

---

## 使用方法

应用以 **accessory** 模式运行（没有 Dock 图标）。所有功能都通过状态栏图标进入：

| 操作 | 方式 |
|---|---|
| 移动卡片 | 拖动卡片上任意非按钮区域 |
| 调整大小 | 拖动右下角的握柄 |
| 播放 / 暂停 / 切歌 | 卡片上的控件——它们真的会驱动 Music.app |
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
* Bundle 中的 `NSAppleEventsUsageDescription` 精确说明了读取什么、发送什么，并且**刻意不**声称可以访问用户的音乐资料库，因为代码从不修改资料库中的任何内容。

### 音频采集权限

Phase 3 需要**第二个、不同的**权限，这里值得说清楚是哪一个，因为它经常被误报：

| | |
|---|---|
| TCC 服务 | **`kTCCServiceAudioCapture`** —— 在系统设置中显示为 **"系统音频录制"** |
| Info.plist 键 | **`NSAudioCaptureUsageDescription`** |
| 屏幕录制 | **不需要** —— 也从未申请 |
| 麦克风 | **不需要** —— 且 `NSMicrophoneUsageDescription` 被刻意移除 |

这些事实来自系统自身的日志与字符串表，而不是凭记忆：

* `tccd` 为音频请求记录的是 `service="kTCCServiceAudioCapture"`。
* 本应用从未申请 `kTCCServiceScreenCapture`。
* `NSAudioCaptureUsageDescription` 是从 `tccd` 的字符串表中读出来的，不是猜的。

屏幕录制与系统音频采集是两个不同的权限，把它们混为一谈是常见错误——本项目自己的历史里也犯过：Phase 1 的 bundle 曾"以防万一"带上了未被使用的 `NSMicrophoneUsageDescription`。该键已被**移除**；申请应用并不使用的权限，正是本项目明令禁止的。

**必须打包成 bundle。** 从 shell 直接启动的裸 Mach-O 没有 bundle 身份，于是 macOS 会把请求归因到**责任进程**——通常是终端——并为那个应用弹出提示。从 shell 启动时，tap 调用阻塞了 **90 秒**，等待一个永远不可能为它作答的权限决定。同样的代码放进签名过的 `.app` bundle，启动耗时 **0.00 秒**。这是一个伪装成代码问题的打包问题，也正是 `scripts/build-tools.sh` 要把探针包进真实 bundle 的原因。

这里没有任何私有 API。特别是**没有使用 MediaRemote**——它虽然能用，但属于私有框架，本项目明确排除。另外要注意 `MPNowPlayingInfoCenter` 帮不上忙：它只报告**调用方自己**的正在播放会话，因此并不存在能那样读取其他应用元数据的公开 API。

---

## Music.app 集成是如何工作的

### 公开 AppleScript，并对照已安装的应用逐一核实

用到的每一个属性都对照应用自身的脚本字典（`sdef /System/Applications/Music.app`）确认过，而不是凭假设：

* `player state` —— 枚举 `ePlS`：`stopped`、`playing`、`paused`、`fast forwarding`、`rewinding`
* `current track`、`player position`
* `track` → `name`、`artist`、`album`、`duration`、`persistent ID`
* `artwork` → `data`（一个 `picture`；Music.app 报告为 `JPEG picture`）
* 命令 `playpause`、`next track`、`previous track`

### 用 `NSAppleScript`，而不是 `osascript`

每次轮询都 spawn 一个 `osascript` 进程会烧 CPU、增加延迟，还会制造大量进程表条目。`NSAppleScript` 在进程内运行，而且脚本**只编译一次并复用**，因此首次调用之后，一次元数据轮询的脚本开销远低于 1 毫秒。在本机实测：**连续读取 5 次耗时 3 毫秒**。

`NSAppleScript` 不是线程安全的，因此所有执行都被限制在单一串行队列上。这同时保证了一个缓慢或卡住的 Music.app 永远不会阻塞 UI 线程。

### 一次往返，而不是九次

单个脚本一次性返回全部九个字段。分别去要标题、艺术家、专辑、时长、位置、状态和封面，意味着每次轮询要九次 Apple Event 往返。唯一的例外是封面，它只在切歌时才去取，因为它是一份独立的 340 KB 负载。

### 播放头插值，并以传输状态为闸门

`player position` 每次轮询读取一次（默认 1.5 秒）。更频繁地取它意味着每帧一次 Apple Event，因此显示位置锚定在最后一次已知值上并在本地推进——但**只在传输处于播放状态时**：

| 状态 | 行为 |
|---|---|
| 播放中 | 推进 |
| 已暂停 | 冻结在锚定值 |
| 已停止 | 冻结 |
| 新曲目 | 重置到新的锚点 |

估计器自身不持有任何时钟：调用方传入 `now`，这使得上述每一种行为都能被直接单元测试。本地估计与一次新读数之间的细微差异被当作抖动忽略；差异很大则被当作 seek 并重新锚定。

快速的 0.5 秒显示定时器**不发送任何** Apple Events——它只是用内存中已有的值重新渲染——并且在暂停期间被完全取消，因此暂停状态的 HUD 不产生任何开销。

### 绝不把启动 Music.app 作为副作用

`tell application "Music"` 会在 Music.app 未运行时启动它。两道防线阻止这件事：

* 先检查 `NSRunningApplication.runningApplications(withBundleIdentifier:)`——公开 AppKit，不产生 Apple Event，不触发启动。
* 在 macOS 15.5 上验证过 `application "Music" is running` **不会**启动该应用，因此脚本内部重复同样的检查，以关闭 Music.app 在两次检查之间退出的竞态。

当 Music.app 未运行时按下传输按钮，什么都不会发生。

---

## 音频采集是如何工作的

**后端：Core Audio process tap。** 之所以选择它而不是 ScreenCaptureKit 或虚拟音频设备，是因为它让 HUD 能够**专门采集 Music.app**——采集整个系统输出会把 Chrome、Discord、通知音和游戏都塞进频谱，而这不是本组件的目的。

```
Music.app
  → Core Audio process object      (kAudioHardwarePropertyTranslatePIDToProcessObject)
  → CATapDescription(stereoMixdownOfProcesses:)
  → AudioHardwareCreateProcessTap  (macOS 14.2+)
  → private aggregate device carrying the tap
  → AudioDeviceCreateIOProcIDWithBlock
  → AudioBufferList  →  RMS / peak  →  diagnostics panel
```

上面每一个符号都是从 macOS 15.5 SDK 头文件中读出来的，然后又在真实音频上跑过，而不是凭假设。应用绝不把启动 Music.app 作为副作用，当 Music.app 退出又重新出现时，tap 会被拆除并重建。

### tap 实际交付了什么

在本机播放 Apple Music 时实测：

| 属性 | 值 |
|---|---|
| 采样率 | **48000 Hz** |
| 声道数 | **2** |
| 格式 | `lpcm`，Float32，**interleaved** |
| 每帧字节数 | 8 |
| 缓冲区大小 | 每次回调 512 帧（约 94 次回调/秒） |
| 实测吞吐 | 约 47600 帧/秒 |

### 真实测得的电平

| 音源状态 | RMS | Peak |
|---|---|---|
| 播放中，安静段落 | −41.3 dBFS | −31.2 dBFS |
| 播放中，响亮段落 | −29.5 dBFS | −18.5 dBFS |
| 曲目中暂停 | **−120.0 dBFS（地板）** | **−120.0 dBFS（地板）** |
| Music.app 已停止 | −120.0 dBFS | −120.0 dBFS |

暂停与停止两行才是关键：回调仍以完整的约 94 次/秒持续到达，只是负载全为零，而面板报告的是 `SILENT`——不是"坏了"。

### 声道处理

所有声道都会被合并：对每个声道累加平方和，RMS 再除以总样本数。相关性立体声——音乐的正常情况——读数与单独任一相同，而硬声像到一侧的能量绝不会被漏掉。其后果已被记录并单元测试：硬声像信号会比单独活跃声道的读数低约 3 dB，因为静音声道也被计入了平均。

### 实时安全性

IOProc 不做任何分配、不记录日志、不用 ObjC、不做 I/O、不做 UI 工作。它在一把短持有的 `os_unfair_lock` 后面把样本折叠进 `LevelAccumulator`，并递增两个计数器。一个 20 Hz 的主线程定时器排空它并发布；音频线程从不触碰任何 `@Published` 属性。诊断输出是每秒一行，绝不按回调输出。

### 状态机

`idle` · `starting` · `receiving` · `silent` · `permissionDenied` · `unsupported` · `failed` · `stopped`。

`AudioCaptureResult` 严格区分 `.noData` 与 `.silence`，因为实测证明它们是真正不同的两种情况：

* Music.app **空闲** → tap **完全不产生回调** → `noData` → `idle`。
* Music.app **曲目中暂停** → 回调持续到达，负载全为零 → `silence` → `silent`。

把这两者当成同一种"不工作"状态，在两个方向上都会出错。

`unsupported` 覆盖 macOS 14.0–14.1，那里没有 process-tap API。包仍然部署到 14.0；只有采集路径被限制到 14.2+。

## 频谱是如何工作的

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
  → 64 log-spaced bands, 20 Hz … 20 kHz
  → noise floor + dynamic range         (map to 0…1)
  → asymmetric attack / release         (smoothing)
  → SpectrumFrame                       (the only thing the renderer sees)
  → SpectrumView                        (a Canvas, nothing more)
```

### 线程模型

| 阶段 | 线程 |
|---|---|
| 混为单声道、推入环形缓冲 | **音频线程** —— 不做 FFT、不分配、不记录日志 |
| 加窗、FFT、分频段、平滑 | **分析队列**（串行，userInitiated） |
| 发布最新帧 | **主 actor** |
| 绘制 | **SwiftUI**，读取最新帧 |

约 94 Hz 的 FFT 速率永远不会变成约 94 Hz 的 UI 速率：分析在自己的队列上运行，SwiftUI 用当前帧重新渲染。音频回调实测**远低于 1 毫秒**，而预算为 10.67 毫秒。

### 两个必须核实、不能假设的 SDK 细节

* **`vDSP_fft_zrip` 自带前向 `scale = 2`。** 它的输出是真实 DFT 的两倍。如果不除掉它，每个读数都会偏高 +6 dB。一个 bin 中心频率上的 0.5 振幅正弦现在能精确还原出 0.5——由测试断言。
* **`vDSP_hann_window` 需要 `vDSP_HANN_DENORM`，** 否则它会乘以 `0.8165`；而且它的公式用 `N`，而不是本项目规定的 `N−1`。因此窗函数在构造时按规定的公式直接计算一次。

振幅归一化除以 `sum(window)`，因此 1024、2048 和 4096 点的 FFT 对同一段音频报告相同的电平——同样由测试断言。

### 频段映射

从 20 Hz 到 20 kHz 按等比数列划分 64 个频段，每个频段以其所有 bin 的 RMS 聚合，而不是取最大值，因为单个 bin 的峰值会逐帧抖动并读作噪声。在约 100 Hz 以下，一个频段**比一个 FFT bin 还窄**，因此低频音的能量会合理地分裂到两个相邻频段；这一点被记录并由测试覆盖，而不是被调参掩盖。

### 与帧率无关的平滑

attack 与 release 被定义为时间常数，并按真实流逝时间换算成每 tick 的系数，因此频谱在 20、30 和 60 FPS 下看起来完全一致。只有 release 可由用户调节；attack 保持快速，以免削弱鼓点瞬态。

## 环境要求与权限

| | |
|---|---|
| macOS | 14.0 或更新（在 **15.5** 上构建并验证） |
| Music.app | 元数据与传输控制**需要**它；HUD 绝不主动启动它 |
| 系统音频录制 | 频谱需要 —— `NSAudioCaptureUsageDescription` |
| 自动化（Apple Events） | 元数据与传输控制需要 —— `NSAppleEventsUsageDescription` |
| 麦克风 | **从不申请，从不使用** |
| 屏幕录制 | **从不申请，从不使用** |

构建出的 `Info.plist` 中只有两个 usage-description 键；可用
`plutil -p "build/Music HUD.app/Contents/Info.plist"` 核实。

### 菜单栏常驻行为

应用以 accessory 模式运行：没有 Dock 图标，没有主菜单栏，只有一个状态栏项。

```
显示 HUD / 隐藏 HUD
窗口层级 · 鼠标穿透模式 · 重置窗口位置
设置… ⌘,     音频诊断… ⌘D
版本 <version>              ← 从 Info.plist 读取，绝不硬编码
退出 Music HUD ⌘Q
```

隐藏 HUD **不会**退出应用，也不会停止音频分析。退出是 `NSApp.terminate`。

### 窗口恢复

只要保存的位置仍然与某块屏幕相交，就会被恢复。如果不相交——例如它原本所在的那块显示器已经不存在——窗口会被移动到当前屏幕上的安全位置，**且不改变尺寸**。被推到屏幕边缘的窗口永远不会被弹回或重新居中。

### 音频采集恢复

process tap 偶尔会向 coreaudiod 注册成功，却什么也不交付，即使音源正在播放。这是操作系统侧的状况，不是权限问题。已在启动的 tap 连续 8 秒没有产生音频后，应用会重建它，最多三次，然后如实报告该状况，而不是无限重试。**已经交付过音频的 tap 永远不会被重建**，因此一段安静的音乐不可能拆掉正在工作的采集。

## Phase 5 —— 视觉打磨

参考图审计与逐项结果：`docs/phase5-reference-audit.md`。

### 改了什么

| 区域 | 改动 | 原因 |
|---|---|---|
| 七段幽灵段 | 笔画宽度 0.16 → **0.095**，alpha 0.06 → **0.045** | 七条点亮权重的圆头笔画会并成一个填充圆角矩形，于是每个数字都坐在一块暗板上，而不是显示出未点亮段的结构 |
| 七段辉光 | 在点亮笔画下增加一层模糊光晕 | 参考图里的数字读起来像发光元件，而不是印刷形状 |
| 频谱频段数 | 48 → **64** | 实测：64 与 48 成本相同（中位数 7.75/8.00% 对 8.75/7.50%——在噪声范围内），且更接近参考图那种更细、更密的柱子。72 的成本是 8.75%，并且看起来像栅栏 |
| 传输 / 缩放的无障碍 | 增加 `accessibilityLabel` 与提示 | VoiceOver 之前只能看到 SF Symbol 的名字 |

### 刻意**没有**改的

窗口行为、整体比例（每个比例都已与参考图相差约 1% 以内）、封面、排版、间距、对齐、背景材质、边框粗细、阴影、FFT 管线、tap、元数据处理与权限。没有明确视觉收益的改动一律拒绝，任何以视觉质量换 CPU 的改动同样拒绝。

### 仅用于快照的插桩

有三个环境变量纯粹是为了让所需的布局快照可以被拍到。它们在正常使用中是惰性的：

| 变量 | 用途 |
|---|---|
| `MUSICHUD_SNAPSHOT_TITLE` / `_ARTIST` / `_ALBUM` | 渲染指定的标题，以便拍下长文本 / CJK 布局用例——真实的 Music.app 资料库无法按需产生这些 |
| `MUSICHUD_SNAPSHOT_WINDOW_SIZE=WxH` | 以最小 / 最大尺寸渲染 |
| `MUSICHUD_SNAPSHOT_ON_AUDIO=1` | 只在真实 FFT 数据开始流动后才拍摄 |

它们**只替换显示文本**，不可能影响音频、FFT 或传输控制。

## Phase 6 —— 信息层级 + 世界时钟

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

`TimeZone.abbreviation(for:)` 与 `localizedName(for:locale:)` 对 ICU 没有短名的时区都会退化成裸的 `GMT±N`，因此本项目要求的 `JST` 和 `BST` 无法从它们那里得到。应用因此**在系统值携带身份信息时使用系统值**，只有当系统返回裸偏移时才使用人工整理的小表。夏令时的判定始终由系统完成。


### 向已有配置中添加城市

`WorldClockStore` 在城市列表之外维护一个 schema 标记（`MusicHUD.worldClock.schema`）。引入上海时，已有配置以**插入方式迁移**：新城市被放到它在轮换中的正确位置（东京之后），每个已有条目都保留其位置与启用/禁用状态。该标记意味着迁移只执行一次——主动删除某个城市的用户，下次启动时不会发现它被复活。

### 布局改动

| 区域 | 改动 |
|---|---|
| 曲目标题 | 11.5 pt semibold → **13 pt bold**，不透明度 0.95 → 0.98 |
| 艺术家行 | 灰 0.46 → **0.62**（中等强调） |
| 专辑 / 来源行 | 9.8 → **9.2 pt**，值不透明度 0.68 → 0.50，标签 0.34 → 0.30 |
| 元数据分隔线 | 不透明度 0.10 → **0.13**，并加入 **8 pt 横向内缩**，使它划分元数据区块而不是横贯整张卡片 |
| Previous / Next | `Previous` → **`PREVIOUS`**，1.0 pt 字距，字重 regular → medium，不透明度 0.42 → 0.54，更大的箭头，以及 82 × 30 pt 的命中区域（无视觉变化） |

层级来自各层之间的**差距**，而不是把所有东西都提亮。

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

值得特别指出的关注点分离：

* **`AppleScriptMusicClient` 是唯一与 Music.app 对话的文件。** 其他一切看到的都是只有四个方法的 `MusicClient`。
* **`AppState` 是组合根。** 脚本客户端位于 app target，provider 位于 logic target；它们只在一个地方被配对，这正是整个 provider 可以对着 mock 测试的原因。
* **没有任何视图调用 AppleScript。** 视图只读 `AppState`，不读别的。
* **logic target 不 import 任何 UI 框架**，这正是它可被测试的原因。

---

## 验证外观与行为

### `scripts/snapshot.sh` —— 无需屏幕录制权限的渲染

```bash
./scripts/snapshot.sh            # writes .build-cache/shots/hud.png
```

**不要在这里相信 `screencapture`。** Phase 1 期间 HUD 看起来完全不可见：窗口在 window server 的屏上列表中，位置和尺寸都正确，进程健康且空闲，但截图里只有壁纸和菜单栏。原因不是渲染 bug——没有屏幕录制权限时，macOS 会静默地**把其他所有进程的窗口**从截图中略去，而桌面图片和菜单栏仍然正常渲染。`ViewSnapshotter` 改为在进程内部渲染视图层级，无需任何权限，也无法说谎。

### `StateTracer` —— 证明随时间变化的行为

```bash
MUSICHUD_TRACE=/tmp/trace.txt MUSICHUD_TRACE_DURATION=30 \
  "build/Music HUD.app/Contents/MacOS/MusicHUD"
```

一张截图只能证明卡片在某一瞬间的样子。它无法证明音乐暂停时播放头**停止**了。追踪器每秒采样一次实时状态，使这些行为可以被验证而不是假设——下面那个播放头 bug 就是这样被发现的。

其他开发用变量：

```bash
MUSICHUD_SNAPSHOT=/tmp/hud.png \
MUSICHUD_SNAPSHOT_SETTINGS=/tmp/settings.png \
MUSICHUD_SNAPSHOT_TAB=music \
  "build/Music HUD.app/Contents/MacOS/MusicHUD"
```

---

## 只有在实际运行时才能发现的 bug

记录下来，因为这两个 bug 在最初写的单元测试里都是隐形的，而且都会以看起来合理的样子发布出去。

**1. AppleScript 把布尔值返回为 `'true'`，而不是 `'bool'`。**
解码器检查的是 descriptor 类型 `'bool'`——这是最显而易见的假设，甚至 Apple 自己的常量就叫这个名字。但一个返回 `true` 的脚本产生的，是类型为 `'true'`（0x74727565）的 null descriptor，于是 `hasTrack` 每次都读回 `false`。卡片显示 "No music playing"，而标题、状态和位置全都读得好好的，这让它看起来完全不像解码问题。`AppleEventDecoding` 现在处理全部三种形式，并有回归测试。

**2. 播放 tick 用一个未锚定的零覆盖了位置。**
当一次读数无法显示时，估计器会被重置，接着 0.5 秒的 tick 就把 `estimate() == 0` 发布到原本有效的值之上。追踪记录显示位置在 `38.83 → 0.00 → 40.05` 之间来回跳。由于 0 是一个完全合理的播放头位置，这次损坏是静默的。现在该 tick 以估计器已锚定为前提做了守卫。

**3. tap 重建路径曾是一个忙循环。**
当 Music.app 退出又重新出现时，恢复逻辑跑在 20 Hz 的电平定时器上。Music.app 在进程出现**之后**的一小段时间才暴露它的 Core Audio process object，因此第一次重建尝试会失败——而重试在 50 毫秒后再次触发，一秒钟内拆建 tap 二十次。一份实时日志显示 0.1 秒内发生了两次尝试。现在只有一个决策点，以及两次尝试之间最少 1.5 秒的间隔。

**4. 频谱绘制正确，而状态机却以为什么都没在播放。**
`CoreAudioTapCapture` 创建了它**自己的** `TapCallbackCounter`，而 service 排空的是另一个从未收到任何东西的实例。引擎是共享的，所以 FFT 正常工作、柱子也是真实的——但 `state` 一直停在 `STARTING`，日志反复打印 "no active PCM"。一个错误，两个互相矛盾的症状。

**5. `onDeviceStarted` 在 `start()` 之后才被赋值。** `start()` 会异步派发设备启动，并在那一刻捕获闭包，所以之后再赋值意味着它永远不会触发，`deviceStarted` 保持 false，而看门狗在音频完美流动的情况下误报 "audio capture permission is not granted"。

**6. supervisor 的 tap 重试可能在 setup 仍在进行时触发。** 由于 setup 变成了异步的，`capture` 会在一段时间内保持 nil，1 Hz 的 supervisor 于是在两秒后建了第二个 tap，丢弃了第一个。现在用世代计数器与 `isSettingUpTap` 标志把它变成 single-flight。

**7. `Frames / s` 报告的是样本数，而不是帧数。** 交织立体声每帧有两个样本，因此 48 kHz 的流在诊断面板里读成 96 kHz。现在除以 `mBytesPerFrame`。

**8. 播放 tick 用一个未锚定的零覆盖了位置（Phase 2）。**
Music.app 对于刚开始串流的曲目，经常还没有封面。把第一次 `nil` 当作事实记录下来，意味着永远注意不到封面后来到达了。现在只缓存成功的读取，并且缺失的封面会在若干次轮询内重试。

---

## 已知限制

**公开 AppleScript 给不了的东西**

* **只有第一张封面。** 读取的是 `data of artwork 1`；一首有多张封面的曲目只会得到一张。
* **拿不到音频流。** 元数据不是音频。实时 PCM 是 Phase 3，完全是另一个问题。
* **`player position` 的精度**就是 Music.app 所报告的那样（约 0.1 秒），这正是显示需要插值的原因。
* **`missing value` 是合法的**，某些媒体类型的 `artist` 等字段就是如此。这些会读成空字符串，而不是让整次轮询失败——有测试覆盖。
* **电台与直播流**没有有意义的时长，因此进度条没有东西可显示。播放头仍然会推进。
* **Music.app 必须已经在运行。** 我们刻意从不启动它。
* 脚本字典里没有任何东西暴露 DRM 或串流质量状态，`lyrics` 属性也刻意不读取（体积大、速度慢、并不需要）。

**音频采集**

* **只有 macOS 14.2 及更新版本**能做 process tap。在 14.0–14.1 上应用报告 `unsupported`，而不是失败。
* **音源空闲时 tap 不报告任何回调。** 运行中但没有播放的 Music.app 什么都不产生，因此"静音"和"没有数据"必须被读作两种不同信号——这正是状态机把它们分开的原因。
* **tap 跟随进程，而不是曲目。** 当 Music.app 退出时，process object 消失，tap 被拆除；当应用回来时它会被重建。
* **`AudioDeviceStart` 在权限提示未作答时会阻塞**——最坏情况下约 90 秒。因此它被派发到主线程之外，并给予 8 秒预算，之后面板报告 `permissionDenied`，而不是看起来卡死。
* **诊断面板是工具，不是产品 UI。** 它从状态栏菜单打开，只在打开期间进行采集，并且与 HUD 没有任何连接。
* 面板中的帧计数针对最近约 50 毫秒的采样窗口；`Frames / s` 那行是单独测量的速率，而不是那个数字乘以 20。

**频谱**

* **CPU 由 UI 呈现主导，而不是 DSP。** FFT 每 tick 约 0.03–0.07 毫秒（约 0.2% CPU）。呈现一帧的开销是对一个 vibrancy 背景窗口做一次完整 UI 更新，实测为 **60 FPS 约 15% CPU、30 FPS 约 8%、20 FPS 约 5%**。因此默认为 **30 FPS**——对这么大尺寸的柱状电平表来说已经很顺滑；60 FPS 仍然可选。DSP 本身从不是瓶颈。
* **约 100 Hz 以下，一个频段比一个 FFT bin 还窄**，因此低频音的能量会分裂到相邻频段，两者都无法还原完整振幅。这是在这个 FFT 尺寸下所选对数映射的必然结果，已被记录并测试，而不是被隐藏。
* **必须在音源确实在产生音频时启动 tap。**
  `AudioHardwareCreateProcessTap` 与聚合设备创建可能阻塞数十秒，因为 coreaudiod 在等待它的 IO context——系统日志显示
  "Starting tap after waiting for writers"，在不同运行中观测到 23.9 秒和 36.7 秒。因此 tap 的建立发生在主线程之外，HUD 永不冻结；期间卡片显示 `STARTING`。
* **没有立体声频谱。** 声道被求和为单声道，正如本项目所规定的。

**其他**
* **桌面层窗口模式**是实验性的：它使用公开的
  `CGWindowLevelForKey(.desktopWindow)`，把卡片放到壁纸之上、桌面图标之下，但 Finder 的桌面窗口位于它上方，因此它可能收不到点击。浮层级别才是可靠的选择，也是默认值。
* **无边框缩放由一个自定义握柄驱动**，因为 AppKit 并不能可靠地为无边框窗口提供原生的边缘拖动缩放。

---

## 路线图

### Phase 3 —— 真实系统音频采集 ✅ 已交付

已验证。见上文"音频采集是如何工作的"。`tools/AudioCaptureProbe.swift` 中的独立探针，在需要脱离应用单独复查管线时仍然有用。

### Phase 4 —— FFT 频谱 ✅ 已交付

已验证。见上文"频谱是如何工作的"。Phase 1 的占位包络被删除了：既然有了真实数据，把合成兜底留在代码库里，就等于长期邀请别人去画假柱子。

### Phase 5–8 —— 打磨与发布

会话 / 进度打磨、键盘快捷键、错误状态、性能工作、签名与公证。

---

## 许可

尚未选定。
