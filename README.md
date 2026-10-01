# Transparent Live Captions

![Transparent Live Captions](docs/screenshot.png)

Windows Live Captions system-audio ASR with a transparent always-on-top overlay, local Japanese/English -> Simplified Chinese translation, and current media-session display/control.

## Architecture

- `overlay/live-captions-lyrics.ps1` — real WPF overlay and Windows Live Captions UIA bridge.
- `translation/translate_worker.py` — Hy-MT2 primary translation engine with one-sentence context and NLLB fallback.
- `media-bridge/` — .NET GlobalSystemMediaTransportControlsSession bridge.
- `%LOCALAPPDATA%\TransparentLiveCaptions` — personal config, IPC, media snapshot and local runtime settings.
- Large model/runtime assets are **not** stored in the project. The local machine currently points `runtime.json` at an external model root.

## Privacy

The normal app runs locally. Caption text is exchanged through short-lived local JSON IPC files only. Do not commit runtime IPC, real captions, media titles, model weights, browser/account data, or user configuration. Cloud translation is not part of the default path.

## Local setup

1. Install Python 3.11 and .NET 9 SDK/runtime.
2. Put the Hy-MT2/NLLB/llama.cpp runtime under a model root (see `docs/MODELS.md`).
3. Run `powershell -ExecutionPolicy Bypass -File .\scripts\Setup-Local.ps1 -ModelRoot <path>`.
4. Run `powershell -ExecutionPolicy Bypass -File .\scripts\Start.ps1`.
5. Optional login startup: `powershell -ExecutionPolicy Bypass -File .\scripts\Register-Startup.ps1`.

## QA demo

`overlay/live-captions-lyrics.ps1 -QaDemo` uses synthetic subtitle/media text. It exists for isolated release QA and does not require reading real caption/media content. Normal launches do not enable this mode.

## Current local product

The production configuration uses Hy-MT2-1.8B Q4_K_M on llama.cpp/Vulkan with one previous source sentence as context and NLLB int8 as runtime fallback. Warm translation inference on the current RTX 4060 Laptop GPU has measured roughly 0.1–0.4 s, while the overlay uses a conservative 700 ms minimum request spacing.

See `docs/PROJECT_STATE.md`, `docs/RUNBOOK.md`, and `docs/KNOWN_ISSUES.md` for current verified state and limitations.
