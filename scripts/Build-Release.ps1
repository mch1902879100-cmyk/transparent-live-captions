param(
    [string]$Version = '0.1.0'
)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$buildRoot=Join-Path $projectRoot 'build-release'
$venv=Join-Path $buildRoot '.venv'
$workerDist=Join-Path $buildRoot 'worker-dist'
$workerWork=Join-Path $buildRoot 'worker-work'
$bridgeOut=Join-Path $buildRoot 'bridge-publish'
$packageRoot=Join-Path $buildRoot ("TransparentLiveCaptions-v"+$Version)
$releaseDir=Join-Path $projectRoot 'release'
$zipPath=Join-Path $releaseDir ("transparent-live-captions-windows-v"+$Version+'.zip')

if(Test-Path -LiteralPath $buildRoot){Remove-Item -LiteralPath $buildRoot -Recurse -Force}
New-Item -ItemType Directory -Path $buildRoot,$releaseDir -Force|Out-Null
py -3.11 -m venv $venv
$python=Join-Path $venv 'Scripts\python.exe'
& $python -m pip install --disable-pip-version-check -q -r (Join-Path $projectRoot 'requirements.txt') pyinstaller==6.21.0
& $python -m PyInstaller --noconfirm --clean --onefile --noconsole --version-file (Join-Path $projectRoot 'packaging\worker-version.txt') --name TransparentLiveCaptionsWorker --distpath $workerDist --workpath $workerWork --specpath $buildRoot (Join-Path $projectRoot 'translation\translate_worker.py')

dotnet publish (Join-Path $projectRoot 'media-bridge\LiveCaptionsMediaBridge.csproj') -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o $bridgeOut

New-Item -ItemType Directory -Path (Join-Path $packageRoot 'overlay'),(Join-Path $packageRoot 'bin'),(Join-Path $packageRoot 'media-bridge'),(Join-Path $packageRoot 'scripts'),(Join-Path $packageRoot 'docs') -Force|Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'overlay\live-captions-lyrics.ps1') -Destination (Join-Path $packageRoot 'overlay\live-captions-lyrics.ps1')
Copy-Item -LiteralPath (Join-Path $workerDist 'TransparentLiveCaptionsWorker.exe') -Destination (Join-Path $packageRoot 'bin\TransparentLiveCaptionsWorker.exe')
Copy-Item -LiteralPath (Join-Path $bridgeOut 'LiveCaptionsMediaBridge.exe') -Destination (Join-Path $packageRoot 'media-bridge\LiveCaptionsMediaBridge.exe')
Copy-Item -LiteralPath (Join-Path $projectRoot 'scripts\Start.ps1'),(Join-Path $projectRoot 'scripts\Stop.ps1'),(Join-Path $projectRoot 'scripts\Register-Startup.ps1'),(Join-Path $projectRoot 'scripts\Unregister-Startup.ps1'),(Join-Path $projectRoot 'scripts\Install-Release.ps1') -Destination (Join-Path $packageRoot 'scripts')
Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md'),(Join-Path $projectRoot 'LICENSE.md') -Destination $packageRoot
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\MODELS.md') -Destination (Join-Path $packageRoot 'docs\MODELS.md')

if(Test-Path -LiteralPath $zipPath){Remove-Item -LiteralPath $zipPath -Force}
Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal
$hash=(Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash
("$hash  "+[IO.Path]::GetFileName($zipPath)) | Set-Content -LiteralPath ($zipPath+'.sha256') -Encoding ASCII
[pscustomobject]@{Version=$Version;Zip=$zipPath;Bytes=(Get-Item $zipPath).Length;SHA256=$hash;PackageRoot=$packageRoot} | ConvertTo-Json -Depth 3
