$ErrorActionPreference='Stop'
$lnk=Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\透明实时字幕.lnk'
if(Test-Path -LiteralPath $lnk){ Remove-Item -LiteralPath $lnk -Force; Write-Host ('Removed startup shortcut: '+$lnk) }
