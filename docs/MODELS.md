# Local model setup

Transparent Live Captions does not redistribute model weights. The primary model is obtained directly from the upstream Tencent Hunyuan release.

## Primary model

- Project: <https://github.com/Tencent-Hunyuan/Hy-MT2>
- Base model: <https://huggingface.co/tencent/Hy-MT2-1.8B>
- Official GGUF: <https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF>
- Recommended file: `Hy-MT2-1.8B-Q4_K_M.gguf`
- Upstream license: Apache-2.0 at the time of this release; always verify the current upstream model card/license before redistribution.

The official GGUF repository documents llama.cpp usage for the `Q4_K_M` quantization. The release package intentionally keeps the model external so users can obtain it from its authoritative source.

## llama.cpp runtime

Use a Windows build of llama.cpp that includes `llama-server.exe` and supports your GPU backend. Upstream project:

<https://github.com/ggerganov/llama.cpp>

The current worker starts `llama-server.exe` on `127.0.0.1`, selects a free port in the 18792-18799 range when available, uses a 2048-token context, and requests GPU layer offload (`-ngl 99`).

## Directory layout

Configure `%LOCALAPPDATA%\TransparentLiveCaptions\runtime.json` with a model root:

```json
{ "modelRoot": "D:\\AIModels\\LiveCaptionTranslation" }
```

Expected layout:

```text
<ModelRoot>/
  models/
    hy-mt2-1.8b-q4/
      Hy-MT2-1.8B-Q4_K_M.gguf
    nllb-int8/
      model.bin
      sentencepiece.bpe.model
      ...
  runtimes/
    llama-b11284/
      llama-server.exe
      ...
```

`nllb-int8` is an optional local runtime fallback. It is not shipped in this repository or release. Its exact weights/provenance are user-supplied, so verify the license of the NLLB distribution you choose before use or redistribution.

## What the app changes compared with a plain model call

The model itself is not retrained by this project. The runtime adapts it to rolling live-caption input by:

- adding at most one previous completed sentence as disambiguation context;
- instructing the model to translate only the current caption, not the context;
- clearing context after 15 seconds of inactivity;
- using deterministic generation settings (`temperature=0.0`, `top_p=0.6`, fixed seed);
- keeping the local model server warm;
- rate-limiting translation requests from rapidly changing captions;
- falling back to local NLLB int8 if the Hy-MT2 path temporarily fails.

Model/runtime files remain subject to their own upstream licenses and are not covered by this repository's source-code distribution status.
