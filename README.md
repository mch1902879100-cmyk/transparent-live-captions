# Transparent Live Captions

> 把 Windows Live Captions 变成真正适合游戏、视频和日语内容的透明双语字幕层。

![Windows](https://img.shields.io/badge/Windows-Live%20Captions-0078D4?logo=windows11&logoColor=white)
![Local First](https://img.shields.io/badge/Translation-Local%20First-2ea44f)
![Hy-MT2](https://img.shields.io/badge/Model-Hy--MT2--1.8B-7c3aed)
![No Cloud Upload](https://img.shields.io/badge/Captions-No%20Cloud%20Upload-black)

![Transparent Live Captions](docs/screenshot.png)

## 还在被 Windows 实时字幕的面板挡住游戏画面吗？

还在因为字幕有一整块背景、看番和玩游戏特别出戏而苦恼吗？<br>
还在因为只有原文字幕，没有“日语 / 英语 + 中文”双语字幕而苦恼吗？<br>
还在担心云端翻译要把每一句字幕都传出去吗？

**Transparent Live Captions** 直接复用 Windows 自带的 Live Captions 语音识别，把原生字幕窗口接管成一个**透明、无边框、始终置顶、可拖动、可缩放的双语字幕层**，并在本机用 Hy-MT2 做中文翻译。

它的目标很简单：

**让字幕像游戏 HUD 一样存在，而不是像另一个窗口挡在你面前。**

## 为什么值得装

| 你真正会感受到的区别 | Transparent Live Captions |
| --- | --- |
| 🎮 游戏沉浸感 | 原生 Live Captions 窗口移出屏幕，只保留透明字幕文字 |
| 🌏 双语字幕 | 原文 + 简体中文翻译同时显示 |
| 🔒 本地优先 | 默认翻译链路完全在本机运行，不上传字幕到云端 |
| ⚡ 面向实时字幕优化 | 对滚动字幕做句尾触发、静默触发、强制刷新和请求去抖 |
| 🧠 上下文翻译 | 给 Hy-MT2 一句之前的字幕做语境，但只输出当前句译文 |
| 🔁 关闭再打开也能接管 | Live Captions 关闭时字幕层隐藏；重新打开后自动重新接管 |
| 🖱️ 像 HUD 一样调 | 可拖动、缩放、锁定、改字号、颜色、位置和显示行数 |
| 🎵 顺手控制媒体 | 可显示当前系统媒体会话并提供上一首 / 播放暂停 / 下一首 |

## 适合这些场景

- 日语游戏、Galgame、JRPG、剧情向游戏：想看原文，也想同时看到中文。
- 没有内置字幕的游戏或视频：直接利用 Windows Live Captions 识别系统声音。
- 看日语直播、访谈、课程：不想让一个大字幕窗口长期盖住内容。
- 英语视频 / 游戏：保留英文原文，同时给出简体中文本地翻译。
- 对隐私敏感：希望字幕文字尽量留在本机，不走云端翻译 API。

## 它是怎么工作的？

```text
游戏 / 视频 / 系统声音
        ↓
Windows Live Captions（负责语音识别 / ASR）
        ↓  UI Automation
Transparent Live Captions
        ├─ 原文透明字幕
        ├─ 本地 Hy-MT2 翻译 → 简体中文
        └─ 系统媒体会话显示 / 控制
```

这里有一个很重要的边界：**Hy-MT2 不是语音识别模型。**

声音先由 Windows Live Captions 转成文字；本项目再读取这段文字并进行显示、滚动字幕处理和本地翻译。因此最终效果同时受 **Windows ASR 准确率** 和 **翻译模型质量** 影响。

## 本地模型：到底从哪里来？

主翻译模型使用腾讯混元团队官方发布的 **Hy-MT2-1.8B**：

- 官方项目：<https://github.com/Tencent-Hunyuan/Hy-MT2>
- 官方原始模型：<https://huggingface.co/tencent/Hy-MT2-1.8B>
- 官方 GGUF：<https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF>
- 本项目推荐量化：`Hy-MT2-1.8B-Q4_K_M.gguf`
- 上游许可证：Apache-2.0（以腾讯官方仓库当前许可证为准）

腾讯官方 GGUF 仓库已经提供 `Q4_K_M` 版本，并给出了 llama.cpp 的本地运行方式。本项目**不会把模型权重重新打包进 Release**；用户直接从上游获取模型，既能减少 Release 体积，也能让模型许可证和来源保持清晰。

## Hy-MT2 的原理是什么？

Hy-MT2 是一个专门面向多语言机器翻译的生成式模型。对本项目来说，可以把它理解为：

1. Windows Live Captions 先得到一段日语或英语文本。
2. 我们把“当前字幕 + 必要的上一句语境”组成翻译指令。
3. Hy-MT2 根据上下文生成简体中文译文。
4. 译文回到透明字幕层，与原文一起显示。

本项目通过 **llama.cpp** 在 `127.0.0.1` 上启动本地 OpenAI-compatible server，并使用 GGUF `Q4_K_M` 量化模型运行。当前生产配置会尽量把模型层放到 GPU 上，以降低实时翻译延迟。

## 我们对“原理”做了哪些工程调整？

我们没有重新训练 Hy-MT2，而是围绕**实时字幕这种连续、会滚动、上下文很短**的输入方式做了工程层优化：

- **一句上下文**：最多带入上一句已完成字幕帮助消歧，但提示词明确要求模型只翻译当前字幕，避免把上文重复输出。
- **上下文自动过期**：长时间没有新字幕时清空历史，避免跨场景串台。
- **确定性解码**：实时翻译使用低随机性的生成参数，减少同一句字幕反复跳词。
- **Q4_K_M + llama.cpp / Vulkan**：用约 1.13 GB 级别的官方 GGUF 量化模型降低显存和加载压力。
- **滚动字幕触发器**：句号等完整句边界优先立即翻译；没有句尾时等待短暂静默；字幕持续滚动时也会强制刷新，避免永远“等字幕停稳”。
- **请求节流**：避免 Windows Live Captions 每次增加几个字都把模型重新轰一遍。
- **旧译文保留**：下一句正在翻译时继续显示上一条已完成译文，不让 UI 一直闪“正在翻译”。
- **短日语片段继承语境**：只含汉字的短日语片段可以继承当前日语会话，减少被误判成中文后直接原样返回。
- **NLLB 本地 fallback**：Hy-MT2 暂时不可用时可回退到本地 NLLB int8 路径。NLLB 权重不随本项目发布，请自行确认对应上游权重的许可证。

在当前开发机的 RTX 4060 Laptop GPU 上，Hy-MT2 热模型推理曾测得约 **0.1–0.4 秒**的常见模型时间；实际端到端字幕延迟还包括 Windows ASR、UIA 轮询、触发策略和字幕本身何时稳定，因此这不是对所有设备的性能承诺。

## v0.1.1：关闭 / 重开也会重新接管

这版修了一个很影响日常使用的生命周期问题。

现在的行为是：

```text
打开 Windows Live Captions
    ↓
透明字幕自动接管
    ↓
关闭 Windows Live Captions
    ↓
透明字幕隐藏，宿主继续等待
    ↓
再次打开 Windows Live Captions
    ↓
自动重新接管新的 LiveCaptions.exe
```

发布前对这个流程做了 **连续 3 轮关闭 → 打开回归测试**，三轮中透明字幕宿主保持同一个进程，每次新启动的 Live Captions 都被重新接管。

## Quick Start

### 方式 A：下载 Release（推荐）

1. 从 GitHub Releases 下载最新 Windows ZIP 并解压。
2. 下载官方 `Hy-MT2-1.8B-Q4_K_M.gguf`，并准备 llama.cpp Windows runtime。
3. 按 `docs/MODELS.md` 建立模型目录。
4. 执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-Release.ps1 -ModelRoot "D:\AIModels\LiveCaptionTranslation" -Start
```

需要开机自动启动时：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-Release.ps1 -ModelRoot "D:\AIModels\LiveCaptionTranslation" -RegisterStartup -Start
```

### 方式 B：从源码运行

需要 Python 3.11 和 .NET 9 SDK/runtime：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Setup-Local.ps1 -ModelRoot "D:\AIModels\LiveCaptionTranslation"
powershell -ExecutionPolicy Bypass -File .\scripts\Start.ps1
```

停止并恢复原生 Windows Live Captions：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Stop.ps1
```

## 模型目录

```text
<ModelRoot>/
  models/
    hy-mt2-1.8b-q4/
      Hy-MT2-1.8B-Q4_K_M.gguf
    nllb-int8/                 # 可选 fallback
      model.bin
      sentencepiece.bpe.model
      ...
  runtimes/
    llama-b11284/
      llama-server.exe
      ...
```

完整说明见 [`docs/MODELS.md`](docs/MODELS.md)。

## 隐私设计

- 默认翻译不调用云端 API。
- Hy-MT2 服务只监听 `127.0.0.1`。
- 字幕请求 / 响应通过 `%LOCALAPPDATA%\TransparentLiveCaptions` 下的短生命周期本地 IPC 文件交换。
- Release 不包含个人字幕历史、媒体标题、用户配置、API Key、模型权重或缓存。
- `-QaDemo` 使用合成字幕和合成媒体信息，用于发布 QA，不需要读取真实字幕内容。

## 当前限制

- 依赖 Windows Live Captions，本项目本身不实现系统音频 ASR。
- 当前本地翻译主要针对 **日语 / 英语 → 简体中文**；中文会直接透传。
- 模型文件和 llama.cpp runtime 需要单独准备，暂未做一键下载器。
- 识别错误来自 Windows ASR 时，翻译模型无法恢复原始声音里没有被正确识别的内容。
- 项目源码目前采用保留权利的发布方式；第三方模型/runtime 继续遵循各自上游许可证。

## English

Transparent Live Captions turns Windows Live Captions into a transparent, borderless, always-on-top bilingual subtitle overlay. It reuses Windows system-audio ASR, translates Japanese / English captions to Simplified Chinese locally with Hy-MT2, automatically reacquires Live Captions after close/reopen cycles, and keeps caption text off cloud translation services by default.

If you are here for gaming: the core idea is simple — **keep the subtitles, lose the bulky caption window.**
