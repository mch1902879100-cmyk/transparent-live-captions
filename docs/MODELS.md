# Model layout

The repository intentionally does not include large model/runtime assets. Configure `runtime.json` under `%LOCALAPPDATA%\TransparentLiveCaptions` with a model root:

```json
{ "modelRoot": "D:\\AIModels\\LiveCaptionTranslation" }
```

Expected layout under that root:

```text
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

The exact model/runtime license is not granted by this repository. Obtain model/runtime files from their respective upstream distributions and comply with those licenses.
