$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$overlay=Join-Path $projectRoot 'overlay\live-captions-lyrics.ps1'
Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$overlay+'"') -WorkingDirectory $projectRoot -WindowStyle Hidden
