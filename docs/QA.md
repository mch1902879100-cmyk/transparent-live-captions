# Release QA

Release builds are produced by `scripts/Build-Release.ps1` from the committed public source.

Release acceptance requires:
- Windows PowerShell 5.1 parse success for the BOM-preserved overlay script.
- Python AST parse success for the source worker.
- self-contained win-x64 media bridge build.
- PyInstaller one-file worker build with ProductVersion/FileVersion 0.1.0.
- privacy/path scan of the repository and package.
- isolated `-QaDemo` visual run with synthetic subtitle/media data only.
- final ZIP SHA256 verification, fresh extraction, and launch.
- GitHub Release re-download hash and fresh-extract launch verification.

The release package intentionally excludes model weights and local runtime configuration.
