$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$overlay=Join-Path $projectRoot 'overlay\live-captions-lyrics.ps1'
$lnk=Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\透明实时字幕.lnk'
$w=New-Object -ComObject WScript.Shell
$s=$w.CreateShortcut($lnk)
$s.TargetPath='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$s.Arguments='-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$overlay+'"'
$s.WorkingDirectory=$projectRoot
$s.Save()
Write-Host ('Registered startup shortcut: '+$lnk)
