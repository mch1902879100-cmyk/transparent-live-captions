$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$overlay=Join-Path $projectRoot 'overlay\live-captions-lyrics.ps1'
& powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $overlay -Stop
