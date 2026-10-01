# 🪟 Transparent Live Captions | 透明实时字幕

> 把 Windows 实时字幕（Live Captions）变成真正适合游戏、视频和日语内容的高颜值双语字幕层。

![Windows](https://img.shields.io/badge/Windows-Live%20Captions-0078D4?logo=windows11&logoColor=white)
![Local First](https://img.shields.io/badge/Translation-Local%20First-2ea44f)
![Hy-MT2](https://img.shields.io/badge/Model-Hy--MT2--1.8B-7c3aed)
![No Cloud Upload](https://img.shields.io/badge/Captions-No%20Cloud%20Upload-black)

![Transparent Live Captions](docs/screenshot.png)

---

### 💡 为什么写这个项目？

平时用电脑看番、玩 Galgame、JRPG，或者刷外语直播时，你是不是也经常遇到这些烦恼：

- 官方的 Windows 实时字幕窗口永远带着一块沉重的背景，挡在游戏画面上，特别出戏。
- 只有孤零零的原文，想要“日语 / 英语 + 简体中文”的双语对照，却找不到顺手的工具。
- 稍微有点隐私敏感，总觉得把每一句字幕都传到云端翻译不太安心。

**Transparent Live Captions** 的想法很简单：**把字幕做成像游戏 HUD 一样轻量、自然的存在。**

它直接复用 Windows 自带的语音识别（ASR），让原本笨重的字幕窗口移出视野，取而代之的是一个**透明、无边框、始终置顶、支持自由拖动和缩放的双语字幕层**，并且默认翻译链路全部在你自己的电脑本地完成。

---

### ✨ 你会感受到的改变

- **🎮 游戏沉浸感拉满**：原生 Live Captions 窗口被移出屏幕，画面上只留下干净的透明字幕文字。
- **🌏 双语同屏显示**：原文与简体中文翻译同时呈现，生肉硬啃不再那么累。
- **🔒 100% 本地优先**：默认翻译链路完全在你的电脑上运行，不把字幕内容上传到云端翻译服务。
- **⚡ 专为实时字幕优化**：针对不断滚动的字幕流做了句尾触发、静默触发、强制刷新和请求去抖，减少文字乱跳和“永远等字幕停稳”的问题。
- **🧠 上下文智能翻译**：支持带入上一句已完成字幕作为语境帮助消歧，但明确要求模型只翻译当前字幕，不重复输出上文。
- **🔁 关掉再开也不用重启**：不小心关掉 Live Captions？字幕层会自动隐藏；重新打开后，会自动重新接管新的 Live Captions 进程。
- **🖱️ 像 HUD 一样自由调节**：位置、大小、字号、颜色、透明度、显示行数都可以自己调，还能锁定位置。
- **🎵 顺手控制媒体**：还能显示当前系统媒体会话，并提供上一首、播放 / 暂停、下一首快捷控制。

---

### 🎯 适合这些场景

- **日语游戏、Galgame、JRPG、剧情向游戏**：想看原文找语感，又想一眼扫到中文不卡壳。
- **没有内置字幕的独立游戏或视频**：直接利用 Windows ASR 给系统声音补上字幕。
- **日语直播、访谈、网课**：不用再忍受一个大字幕窗口长期盖住画面核心内容。
- **英语学习 / 娱乐**：保留英文原文，同时实时看到简体中文翻译。
- **对隐私比较敏感**：希望字幕文本尽量留在本机，不经过云端翻译 API。

---

### ⚙️ 它是怎么工作的？

整个链路很轻量：

```text
游戏 / 视频 / 系统声音
        ↓
Windows Live Captions（负责语音识别 / ASR）
        ↓  UI Automation
Transparent Live Captions
        ├─ 渲染原文透明字幕
        ├─ 调用本地 Hy-MT2 翻译 → 简体中文
        └─ 同步显示 / 控制系统媒体会话
```

> ⚠️ **一个重要边界**：本项目不包含自己的语音识别模型。声音先由 Windows Live Captions 转成文字，我们负责接管显示、优化滚动字幕和本地翻译。所以最终准确率会同时受到 **Windows ASR 水平** 和 **翻译模型质量** 的影响。

---

### 🤖 本地模型：到底从哪里来？

为了兼顾翻译质量、延迟和隐私，本项目主推腾讯混元团队官方发布的 **Hy-MT2-1.8B**：

- **官方项目**：<https://github.com/Tencent-Hunyuan/Hy-MT2>
- **官方原始模型**：<https://huggingface.co/tencent/Hy-MT2-1.8B>
- **官方 GGUF**：<https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF>
- **推荐量化版本**：`Hy-MT2-1.8B-Q4_K_M.gguf`，约 1.13 GB
- **上游许可证**：Apache-2.0（请始终以上游当前仓库 / Model Card 为准）

本项目**不会把模型权重重新打包进 Release**。模型请直接从腾讯官方或其官方 Hugging Face 仓库获取，这样来源更清晰，也能让应用下载包保持轻巧。

本地推理由 **llama.cpp** 提供，默认只监听 `127.0.0.1`。在当前开发机的 RTX 4060 Laptop GPU 上，热模型推理常见约 **0.1–0.4 秒**；实际端到端字幕延迟还会受到 Windows ASR、字幕触发时机和设备性能影响，因此这不是对所有机器的性能承诺。

---

### 🧠 我们是怎么把普通模型调用改造成“实时字幕翻译”的？

我们没有重新训练 Hy-MT2，而是围绕**字幕会持续滚动、片段很短、上下文容易断**这几个问题做了一层实时翻译工程：

- **一句上下文消歧**：最多带入上一句已完成字幕，让模型知道当前人物 / 话题在说什么，但只输出当前句译文。
- **上下文自动过期**：长时间没有新字幕时自动清空，避免换场景后“串台”。
- **句尾优先触发**：遇到完整句边界尽快翻译。
- **短静默触发**：没有句号也不用一直等，短暂停顿后就会送去翻译。
- **强制滚动刷新**：字幕一直变化也会定期翻译，避免永远停在“等字幕稳定”。
- **请求去抖 / 节流**：不会因为 Windows Live Captions 每多识别几个字就疯狂重复调用模型。
- **保留上一条译文**：下一句正在翻译时继续显示上一条完成结果，减少 UI 闪烁。
- **短日语片段继承语境**：只有汉字的短日语片段也可以沿用当前日语会话，减少被误判成中文直接原样输出。
- **本地 fallback**：Hy-MT2 临时不可用时，可以回退到可选的本地 NLLB int8 路径。

这些调整的目的不是让模型“变成另一个模型”，而是让它更适合**每几百毫秒都可能变化一次的实时字幕流**。

---

### 🔁 v0.1.1：关闭 Live Captions，再打开也会自动回来

这版重点修了一个非常影响日常使用的生命周期问题。

现在的行为是：

```text
打开 Windows Live Captions
        ↓
透明字幕自动接管
        ↓
关闭 Windows Live Captions
        ↓
透明字幕隐藏，但宿主继续等待
        ↓
再次打开 Windows Live Captions
        ↓
自动重新接管新的 LiveCaptions.exe
```

发布前我们对这个流程做了**连续 3 轮真实关闭 → 打开回归测试**：同一个透明字幕宿主在三轮里都保持存活，并成功重新接管每次新启动的 Live Captions。

---

### 🚀 快速开始

#### 方式 A：下载 Release（推荐日常使用）

1. 从 GitHub Releases 下载最新 Windows ZIP 并解压。
2. 下载官方 `Hy-MT2-1.8B-Q4_K_M.gguf` 模型，并准备一个支持你显卡后端的 llama.cpp Windows runtime。
3. 按 [`docs/MODELS.md`](docs/MODELS.md) 的目录结构放好模型和 runtime。
4. 打开 PowerShell 运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-Release.ps1 -ModelRoot "D:\AIModels\LiveCaptionTranslation" -Start
```

如果希望开机自启，加上 `-RegisterStartup`：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-Release.ps1 -ModelRoot "D:\AIModels\LiveCaptionTranslation" -RegisterStartup -Start
```

#### 方式 B：从源码运行（开发者适用）

环境需求：Python 3.11 + .NET 9 SDK / runtime。

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Setup-Local.ps1 -ModelRoot "D:\AIModels\LiveCaptionTranslation"
powershell -ExecutionPolicy Bypass -File .\scripts\Start.ps1
```

想停止 Transparent Live Captions，并恢复 Windows 原生字幕窗口：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Stop.ps1
```

---

### 📁 模型目录

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

---

### 🔒 隐私设计

- 默认翻译不调用云端 API。
- Hy-MT2 / llama.cpp 服务只监听 `127.0.0.1`。
- 字幕请求 / 响应只通过 `%LOCALAPPDATA%\TransparentLiveCaptions` 下的短生命周期本地 IPC 文件交换。
- Release 不包含个人字幕历史、媒体标题、用户配置、API Key、模型权重或缓存。
- 发布 QA 使用合成字幕 / 合成媒体信息，不需要把真实字幕内容写进测试材料。

---

### ⚠️ 当前边界

- 依赖 Windows Live Captions，本项目本身不做系统音频 ASR。
- 当前本地翻译主要针对 **日语 / 英语 → 简体中文**；中文会直接透传。
- 模型文件和 llama.cpp runtime 需要单独准备，暂时还没有一键下载器。
- 如果 Windows ASR 本身把声音识别错了，翻译模型无法恢复原始音频里已经丢失的信息。
- 项目源码目前采用保留权利的发布方式；第三方模型和 runtime 继续遵循各自上游许可证。

---

如果你也受够了官方字幕那个碍眼的“大窗口”，不妨试试看。

**让双语字幕真正像游戏 HUD 一样，自然地融进屏幕里。**

### English

Transparent Live Captions turns Windows Live Captions into a transparent, borderless, always-on-top bilingual subtitle HUD. It reuses Windows system-audio ASR, translates Japanese / English captions to Simplified Chinese locally with Hy-MT2, automatically reacquires Live Captions after close/reopen cycles, and keeps caption text off cloud translation services by default.

**Keep the subtitles. Lose the bulky window.**
