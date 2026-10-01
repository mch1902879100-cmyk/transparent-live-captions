param(
    [Parameter(Mandatory)][string]$ModelRoot,
    [switch]$RegisterStartup,
    [switch]$Start
)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$resolved=(Resolve-Path -LiteralPath $ModelRoot).Path
$runtimeRoot=Join-Path $env:LOCALAPPDATA 'TransparentLiveCaptions'
New-Item -ItemType Directory -Path $runtimeRoot -Force|Out-Null
@{modelRoot=$resolved} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runtimeRoot 'runtime.json') -Encoding UTF8
if($RegisterStartup){ & (Join-Path $projectRoot 'scripts\Register-Startup.ps1') }
if($Start){ & (Join-Path $projectRoot 'scripts\Start.ps1') }
Write-Host ('Configured model root: '+$resolved)
