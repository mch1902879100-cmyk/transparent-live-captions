param(
    [Parameter(Mandatory)][string]$ModelRoot,
    [switch]$RegisterStartup
)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$runtimeRoot=Join-Path $env:LOCALAPPDATA 'TransparentLiveCaptions'
New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
@{modelRoot=(Resolve-Path -LiteralPath $ModelRoot).Path} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runtimeRoot 'runtime.json') -Encoding UTF8
if(!(Test-Path (Join-Path $projectRoot '.venv\Scripts\python.exe'))){ py -3.11 -m venv (Join-Path $projectRoot '.venv') }
& (Join-Path $projectRoot '.venv\Scripts\python.exe') -m pip install --disable-pip-version-check -r (Join-Path $projectRoot 'requirements.txt')
dotnet publish (Join-Path $projectRoot 'media-bridge\LiveCaptionsMediaBridge.csproj') -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true
if($RegisterStartup){ & (Join-Path $projectRoot 'scripts\Register-Startup.ps1') }
Write-Host 'Transparent Live Captions local setup complete.'
