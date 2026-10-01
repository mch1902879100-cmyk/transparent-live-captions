param([switch]$Stop, [switch]$QaDemo)

$ErrorActionPreference = 'Stop'
$scriptPath = $PSCommandPath
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)
$runtimeRoot = Join-Path $env:LOCALAPPDATA 'TransparentLiveCaptions'
$configPath = Join-Path $runtimeRoot 'config.json'
$runtimeConfigPath = Join-Path $runtimeRoot 'runtime.json'
$ipcRoot = Join-Path $runtimeRoot 'ipc'
$mediaRoot = Join-Path $runtimeRoot 'media'
$mediaSnapshotPath = Join-Path $mediaRoot 'current.json'
$mediaBridgeExe = Join-Path $projectRoot 'media-bridge\LiveCaptionsMediaBridge.exe'
if (-not (Test-Path -LiteralPath $mediaBridgeExe)) {
    $mediaBridgeExe = Join-Path $projectRoot 'media-bridge\bin\Release\net9.0-windows10.0.19041.0\win-x64\publish\LiveCaptionsMediaBridge.exe'
}
$translationScript = Join-Path $projectRoot 'translation\translate_worker.py'
$translationPythonw = Join-Path $projectRoot '.venv\Scripts\pythonw.exe'
$translationWorkerExe = Join-Path $projectRoot 'bin\TransparentLiveCaptionsWorker.exe'
$translationRequestPath = Join-Path $ipcRoot 'request.json'
$translationResponsePath = Join-Path $ipcRoot 'response.json'
$modelRoot = Join-Path $runtimeRoot 'models'
New-Item -ItemType Directory -Path $runtimeRoot, $ipcRoot, $mediaRoot -Force | Out-Null
if (Test-Path -LiteralPath $runtimeConfigPath) {
    try {
        $runtimeConfig = Get-Content -Raw -Encoding UTF8 -LiteralPath $runtimeConfigPath | ConvertFrom-Json
        if ($runtimeConfig.modelRoot) { $modelRoot = [string]$runtimeConfig.modelRoot }
    } catch {}
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, UIAutomationClient, UIAutomationTypes
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LyricsNative {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll", EntryPoint="GetWindowLong")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", EntryPoint="SetWindowLong")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int value);
    [DllImport("user32.dll")] public static extern bool SetLayeredWindowAttributes(IntPtr hWnd, uint colorKey, byte alpha, uint flags);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr insertAfter, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern void keybd_event(byte virtualKey, byte scanCode, uint flags, UIntPtr extraInfo);
    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hWnd, int attribute, ref int value, int size);
    public static void SetCloaked(IntPtr hWnd, bool cloaked) {
        int value = cloaked ? 1 : 0;
        DwmSetWindowAttribute(hWnd, 13, ref value, sizeof(int));
    }
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    public static IntPtr FindWindowForProcess(int targetProcessId) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((hWnd, lParam) => {
            uint processId;
            GetWindowThreadProcessId(hWnd, out processId);
            if (processId == targetProcessId) { found = hWnd; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
'@

function Restore-LiveCaptions {
    [System.Diagnostics.Process]::GetProcessesByName('LiveCaptions') |
        ForEach-Object {
            $handle = [LyricsNative]::FindWindowForProcess($_.Id)
            if ($handle -ne [IntPtr]::Zero) {
                [LyricsNative]::SetCloaked($handle, $false)
                [LyricsNative]::SetLayeredWindowAttributes($handle, 0, 255, 2) | Out-Null
                [LyricsNative]::SetWindowPos($handle, [IntPtr]::Zero, 0, 0, 0, 0, 0x0015) | Out-Null
                [LyricsNative]::ShowWindowAsync($handle, 5) | Out-Null
            }
        }
}

if ($Stop) {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -like "*$scriptPath*" -and $_.CommandLine -notlike '*-Stop*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Restore-LiveCaptions
    exit 0
}

if (-not $QaDemo -and -not (Get-Process -Name LiveCaptions -ErrorAction SilentlyContinue)) {
    Start-Process (Join-Path $env:WINDIR 'System32\LiveCaptions.exe')
    Start-Sleep -Seconds 2
}

$mutexName = if ($QaDemo) { 'Global\TransparentLiveCaptionsQaDemo' } else { 'Global\LiveCaptionsLyricsOverlay' }
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0, $false)) { exit 0 }

if (-not $QaDemo -and (Test-Path -LiteralPath $mediaBridgeExe)) {
    $bridgeName = [System.IO.Path]::GetFileName($mediaBridgeExe)
    Get-CimInstance Win32_Process -Filter "Name = '$bridgeName'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*watch*current.json*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    $bridgeArgs = 'watch "' + $mediaSnapshotPath + '" ' + $PID
    $script:mediaBridgeWatcher = Start-Process -FilePath $mediaBridgeExe -ArgumentList $bridgeArgs -WindowStyle Hidden -PassThru
}
if ((Test-Path -LiteralPath $translationWorkerExe) -or ((Test-Path -LiteralPath $translationPythonw) -and (Test-Path -LiteralPath $translationScript))) {
    New-Item -ItemType Directory -Path $ipcRoot -Force | Out-Null
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.Name -eq 'pythonw.exe' -and $_.CommandLine -like ("*" + $translationScript + "*") -and $_.CommandLine -like ("*" + $translationRequestPath + "*")) -or
            ($_.Name -eq 'TransparentLiveCaptionsWorker.exe' -and $_.CommandLine -like ("*" + $translationRequestPath + "*"))
        } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $translationRequestPath, $translationResponsePath -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $translationWorkerExe) {
        $translationArgs = '"' + $translationRequestPath + '" "' + $translationResponsePath + '" ' + $PID + ' "' + $modelRoot + '"'
        $script:translationWorker = Start-Process -FilePath $translationWorkerExe -ArgumentList $translationArgs -WindowStyle Hidden -PassThru
    } else {
        $translationArgs = '"' + $translationScript + '" "' + $translationRequestPath + '" "' + $translationResponsePath + '" ' + $PID + ' "' + $modelRoot + '"'
        $script:translationWorker = Start-Process -FilePath $translationPythonw -ArgumentList $translationArgs -WindowStyle Hidden -PassThru
    }
}

$window = New-Object System.Windows.Window
$window.Title = if ($QaDemo) { 'Transparent Live Captions QA' } else { 'Transparent Live Captions' }
$window.WindowStyle = [System.Windows.WindowStyle]::None
$window.AllowsTransparency = $true
$window.Background = [System.Windows.Media.Brushes]::Transparent
$window.Topmost = $true
$window.ShowInTaskbar = $false
$window.ResizeMode = [System.Windows.ResizeMode]::NoResize
$window.SizeToContent = [System.Windows.SizeToContent]::Manual
$window.ResizeMode = [System.Windows.ResizeMode]::CanResize
$window.Left = 0
$window.Top = [Math]::Max(80, [System.Windows.SystemParameters]::PrimaryScreenHeight - 250)
$window.IsHitTestVisible = $true

$caption = New-Object System.Windows.Controls.TextBlock
$caption.TextAlignment = [System.Windows.TextAlignment]::Center
$caption.TextWrapping = [System.Windows.TextWrapping]::Wrap
$caption.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
$caption.FontSize = 31
$caption.FontWeight = [System.Windows.FontWeights]::SemiBold
$caption.Foreground = [System.Windows.Media.Brushes]::White
$caption.Margin = New-Object System.Windows.Thickness(28, 14, 28, 0)
$caption.Cursor = [System.Windows.Input.Cursors]::SizeAll
$caption.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
$shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
$shadow.Color = [System.Windows.Media.Colors]::Black
$shadow.BlurRadius = 2
$shadow.ShadowDepth = 2
$shadow.Opacity = 1
$caption.Effect = $shadow
$subtitleStack = New-Object System.Windows.Controls.StackPanel
$subtitleStack.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
$subtitleStack.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
$subtitleStack.Margin = New-Object System.Windows.Thickness(0, 0, 0, 48)
$subtitleStack.Background = [System.Windows.Media.Brushes]::Transparent
$subtitleStack.Cursor = [System.Windows.Input.Cursors]::SizeAll
[void]$subtitleStack.Children.Add($caption)
$translationText = New-Object System.Windows.Controls.TextBlock
$translationText.Text = '离线翻译模型加载中…'
$translationText.TextAlignment = [System.Windows.TextAlignment]::Center
$translationText.TextWrapping = [System.Windows.TextWrapping]::Wrap
$translationText.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
$translationText.FontSize = 23
$translationText.FontWeight = [System.Windows.FontWeights]::Medium
$translationText.Foreground = [System.Windows.Media.Brushes]::LightCyan
$translationText.Margin = New-Object System.Windows.Thickness(24, 2, 24, 0)
$translationText.Effect = $shadow
[void]$subtitleStack.Children.Add($translationText)
$frame = New-Object System.Windows.Controls.Border
$frame.BorderThickness = New-Object System.Windows.Thickness(1)
$frame.Padding = New-Object System.Windows.Thickness(0)
$grid = New-Object System.Windows.Controls.Grid
$grid.Children.Add($subtitleStack) | Out-Null
$mediaControls = New-Object System.Windows.Controls.StackPanel
$mediaControls.Orientation = [System.Windows.Controls.Orientation]::Vertical
$mediaControls.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
$mediaControls.VerticalAlignment = [System.Windows.VerticalAlignment]::Bottom
$mediaControls.Margin = New-Object System.Windows.Thickness(0, 0, 0, 2)
$mediaControls.Visibility = [System.Windows.Visibility]::Collapsed
$mediaControls.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(210, 245, 245, 245))
$mediaTitle = New-Object System.Windows.Controls.TextBlock
$mediaTitle.Text = '读取系统媒体会话…'
$mediaTitle.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
$mediaTitle.FontSize = 12
$mediaTitle.Foreground = [System.Windows.Media.Brushes]::DimGray
$mediaTitle.TextAlignment = [System.Windows.TextAlignment]::Center
$mediaTitle.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
$mediaTitle.Margin = New-Object System.Windows.Thickness(12, 4, 12, 0)
$mediaTitle.MaxWidth = 660
$mediaControls.Children.Add($mediaTitle) | Out-Null
$transportButtons = New-Object System.Windows.Controls.StackPanel
$transportButtons.Orientation = [System.Windows.Controls.Orientation]::Horizontal
$transportButtons.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
function New-MediaButton([string]$Glyph, [string]$Tip, [string]$Command, [byte]$VirtualKey) {
    $button = New-Object System.Windows.Controls.Button
    $button.Width = 58
    $button.Height = 34
    $button.Padding = New-Object System.Windows.Thickness(8, 4, 8, 4)
    $button.BorderThickness = New-Object System.Windows.Thickness(0)
    $button.Background = [System.Windows.Media.Brushes]::Transparent
    $button.ToolTip = $Tip
    $button.Cursor = [System.Windows.Input.Cursors]::Hand
    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = $Glyph
    $label.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI Symbol')
    $label.FontSize = 18
    $label.Foreground = [System.Windows.Media.Brushes]::DimGray
    $label.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    $label.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $button.Content = $label
    $button.Add_Click({
        if (Test-Path -LiteralPath $mediaBridgeExe) {
            Start-Process -FilePath $mediaBridgeExe -ArgumentList ('command ' + $Command) -WindowStyle Hidden
        } else {
            [LyricsNative]::keybd_event($VirtualKey, 0, 0, [UIntPtr]::Zero)
            [LyricsNative]::keybd_event($VirtualKey, 0, 2, [UIntPtr]::Zero)
        }
    }.GetNewClosure())
    return $button
}
$previousButton = New-MediaButton '⏮' '上一首' 'previous' 0xB1
$toggleButton = New-MediaButton '▶' '播放 / 暂停' 'toggle' 0xB3
$nextButton = New-MediaButton '⏭' '下一首' 'next' 0xB0
[void]$transportButtons.Children.Add($previousButton)
[void]$transportButtons.Children.Add($toggleButton)
[void]$transportButtons.Children.Add($nextButton)
$translateButton = New-Object System.Windows.Controls.Button
$translateButton.Width = 50
$translateButton.Height = 34
$translateButton.Padding = New-Object System.Windows.Thickness(8, 4, 8, 4)
$translateButton.BorderThickness = New-Object System.Windows.Thickness(0)
$translateButton.Background = [System.Windows.Media.Brushes]::Transparent
$translateButton.ToolTip = '开关简体中文离线翻译'
$translateButton.Cursor = [System.Windows.Input.Cursors]::Hand
$translateLabel = New-Object System.Windows.Controls.TextBlock
$translateLabel.Text = '译'
$translateLabel.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
$translateLabel.FontSize = 16
$translateLabel.Foreground = [System.Windows.Media.Brushes]::DimGray
$translateLabel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
$translateLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
$translateButton.Content = $translateLabel
[void]$transportButtons.Children.Add($translateButton)
$mediaControls.Children.Add($transportButtons) | Out-Null
$grid.Children.Add($mediaControls) | Out-Null
$lockButton = New-Object System.Windows.Controls.Button
$lockButton.Width = 50
$lockButton.Height = 24
$lockButton.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
$lockButton.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
$lockButton.Margin = New-Object System.Windows.Thickness(0, 5, 6, 0)
$lockButton.Opacity = 0.72
$lockButton.Cursor = [System.Windows.Input.Cursors]::Hand
$lockButton.ToolTip = '锁定 / 解锁字幕位置'
$grid.Children.Add($lockButton) | Out-Null
$leftGrip = New-Object System.Windows.Controls.Primitives.Thumb
$leftGrip.Width = 14
$leftGrip.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
$leftGrip.Cursor = [System.Windows.Input.Cursors]::SizeWE
$leftGrip.Background = [System.Windows.Media.Brushes]::Transparent
$leftGrip.BorderBrush = [System.Windows.Media.Brushes]::Transparent
$leftGrip.Opacity = 0
$rightGrip = New-Object System.Windows.Controls.Primitives.Thumb
$rightGrip.Width = 14
$rightGrip.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
$rightGrip.Cursor = [System.Windows.Input.Cursors]::SizeWE
$rightGrip.Background = [System.Windows.Media.Brushes]::Transparent
$rightGrip.BorderBrush = [System.Windows.Media.Brushes]::Transparent
$rightGrip.Opacity = 0
$topGrip = New-Object System.Windows.Controls.Primitives.Thumb
$topGrip.Height = 14
$topGrip.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
$topGrip.Cursor = [System.Windows.Input.Cursors]::SizeNS
$topGrip.Opacity = 0
$bottomGrip = New-Object System.Windows.Controls.Primitives.Thumb
$bottomGrip.Height = 14
$bottomGrip.VerticalAlignment = [System.Windows.VerticalAlignment]::Bottom
$bottomGrip.Cursor = [System.Windows.Input.Cursors]::SizeNS
$bottomGrip.Opacity = 0
$grid.Children.Add($leftGrip) | Out-Null
$grid.Children.Add($rightGrip) | Out-Null
$grid.Children.Add($topGrip) | Out-Null
$grid.Children.Add($bottomGrip) | Out-Null
$frame.Child = $grid
$window.Content = $frame

$settings = @{ FontSize = 31; Color = 'White'; Position = 'Bottom'; Lines = 2; Left = 0; Top = -1; Width = 900; Height = 200; Locked = $false; Translate = $true }
if (Test-Path -LiteralPath $configPath) {
    try {
        $saved = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
        foreach ($name in @($settings.Keys)) { if ($null -ne $saved.$name) { $settings[$name] = $saved.$name } }
    } catch {}
}
function Test-OverlayGeometryVisible {
    param(
        [double]$Left,
        [double]$Top,
        [double]$Width,
        [double]$Height,
        [double]$VirtualLeft,
        [double]$VirtualTop,
        [double]$VirtualWidth,
        [double]$VirtualHeight
    )
    $virtualRight = $VirtualLeft + $VirtualWidth
    $virtualBottom = $VirtualTop + $VirtualHeight
    if (($Left + $Width) -lt ($VirtualLeft + 100) -or $Left -gt ($virtualRight - 100)) { return $false }
    if ($Top -ge 0 -and (($Top + $Height) -lt ($VirtualTop + 60) -or $Top -gt ($virtualBottom - 60))) { return $false }
    return $true
}

function Repair-OverlayGeometry {
    param([hashtable]$Settings)
    $virtualLeft = [double][System.Windows.SystemParameters]::VirtualScreenLeft
    $virtualTop = [double][System.Windows.SystemParameters]::VirtualScreenTop
    $virtualWidth = [double][System.Windows.SystemParameters]::VirtualScreenWidth
    $virtualHeight = [double][System.Windows.SystemParameters]::VirtualScreenHeight
    $Settings.Width = [int][Math]::Max(260, [Math]::Min([double]$Settings.Width, [Math]::Max(260, $virtualWidth)))
    $Settings.Height = [int][Math]::Max(70, [Math]::Min([double]$Settings.Height, [Math]::Max(70, $virtualHeight)))
    if (-not (Test-OverlayGeometryVisible -Left ([double]$Settings.Left) -Top ([double]$Settings.Top) -Width ([double]$Settings.Width) -Height ([double]$Settings.Height) -VirtualLeft $virtualLeft -VirtualTop $virtualTop -VirtualWidth $virtualWidth -VirtualHeight $virtualHeight)) {
        $Settings.Left = [int](([System.Windows.SystemParameters]::PrimaryScreenWidth - [double]$Settings.Width) / 2)
        $Settings.Top = -1
    }
}

# Keep positions on an active left-hand monitor, but recover stale coordinates
# after display layouts change by checking the full virtual desktop.
Repair-OverlayGeometry -Settings $settings

function Apply-Settings {
    $window.Width = [double]$settings.Width
    $window.Height = [Math]::Max(100, ([double]$settings.FontSize * 1.6 * [int]$settings.Lines) + 144)
    $caption.FontSize = [double]$settings.FontSize
    $caption.Foreground = [System.Windows.Media.Brushes]::$($settings.Color)
    $caption.MaxHeight = $window.Height - 144
    $translationText.Visibility = if ($settings.Translate) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $translationText.MaxHeight = [Math]::Max(30, ($window.Height - 144) / 2)
    $translationText.MaxWidth = [Math]::Max(180, $window.Width - 48)
    $translateLabel.Foreground = if ($settings.Translate) { [System.Windows.Media.Brushes]::DodgerBlue } else { [System.Windows.Media.Brushes]::DimGray }
    $mediaTitle.MaxWidth = [Math]::Max(220, $window.Width - 24)
    $screenHeight = [System.Windows.SystemParameters]::PrimaryScreenHeight
    $window.Top = switch ($settings.Position) {
        'Top' { 80 }
        'Middle' { [Math]::Max(80, ($screenHeight - $window.Height) / 2) }
        default { [Math]::Max(80, $screenHeight - 250) }
    }
    if ([double]$settings.Top -ge 0) {
        $window.Top = [double]$settings.Top
        $window.Left = [double]$settings.Left
    } else {
        $window.Left = ([System.Windows.SystemParameters]::PrimaryScreenWidth - $window.Width) / 2
    }
    $caption.MaxWidth = [Math]::Max(180, $window.Width - 56)
    $lockButton.Content = if ($settings.Locked) { '解锁' } else { '锁定' }
    $window.Cursor = if ($settings.Locked) { [System.Windows.Input.Cursors]::Arrow } else { [System.Windows.Input.Cursors]::SizeAll }
    $lockButton.Visibility = [System.Windows.Visibility]::Collapsed
    $window.ResizeMode = if ($settings.Locked) { [System.Windows.ResizeMode]::NoResize } else { [System.Windows.ResizeMode]::CanResize }
    $leftGrip.Visibility = if ($settings.Locked) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
    $rightGrip.Visibility = if ($settings.Locked) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
    $topGrip.Visibility = if ($settings.Locked) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
    $bottomGrip.Visibility = if ($settings.Locked) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
    $frame.Background = [System.Windows.Media.Brushes]::Transparent
    $frame.BorderBrush = [System.Windows.Media.Brushes]::Transparent
    $settings | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding utf8
}

$panel = New-Object System.Windows.Window
$panel.Title = 'Transparent Captions'
$panel.Width = 290
$panel.Height = 310
$panel.Topmost = $true
$panel.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
$panel.Left = [System.Windows.SystemParameters]::PrimaryScreenWidth - 320
$panel.Top = 80
$stack = New-Object System.Windows.Controls.StackPanel
$stack.Margin = New-Object System.Windows.Thickness(16)
function Add-Label([string]$Value) { $label=New-Object System.Windows.Controls.TextBlock; $label.Text=$Value; $label.Margin=New-Object System.Windows.Thickness(0,8,0,3); $stack.Children.Add($label) | Out-Null }
Add-Label 'Text size'
$size = New-Object System.Windows.Controls.Slider; $size.Minimum=18; $size.Maximum=56; $size.Value=$settings.FontSize; $size.TickFrequency=2; $stack.Children.Add($size) | Out-Null
Add-Label 'Text color'
$color = New-Object System.Windows.Controls.ComboBox; @('White','Yellow','Cyan','Lime','Orange') | ForEach-Object { [void]$color.Items.Add($_) }; $color.SelectedItem=$settings.Color; $stack.Children.Add($color) | Out-Null
Add-Label 'Screen position'
$position = New-Object System.Windows.Controls.ComboBox; @('Top','Middle','Bottom') | ForEach-Object { [void]$position.Items.Add($_) }; $position.SelectedItem=$settings.Position; $stack.Children.Add($position) | Out-Null
Add-Label 'Visible lines'
$lines = New-Object System.Windows.Controls.ComboBox; @(1,2,3,4) | ForEach-Object { [void]$lines.Items.Add($_) }; $lines.SelectedItem=[int]$settings.Lines; $stack.Children.Add($lines) | Out-Null
$panel.Content = $stack
$update = {
    $settings.FontSize=[int][Math]::Round($size.Value)
    $settings.Color=[string]$color.SelectedItem
    $settings.Position=[string]$position.SelectedItem
    $settings.Lines=[int]$lines.SelectedItem
    Apply-Settings
}
$size.Add_ValueChanged($update); $color.Add_SelectionChanged($update); $position.Add_SelectionChanged($update); $lines.Add_SelectionChanged($update)
Apply-Settings
$translateButton.Add_Click({
    $settings.Translate = -not [bool]$settings.Translate
    $script:lastTranslationSource = ''
    $script:translationSequence++
    $script:translationRequests = @{}
    $script:lastCaptionChangedAt = [DateTime]::UtcNow
    Apply-Settings
    $settings | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding utf8
})
$window.Add_PreviewMouseLeftButtonDown({
    param($sender, $event)
    if ($settings.Locked) { return }
    $node = $event.OriginalSource
    while ($node -is [System.Windows.DependencyObject]) {
        if ($node -is [System.Windows.Controls.Button] -or $node -is [System.Windows.Controls.Primitives.Thumb]) { return }
        try { $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node) } catch { break }
    }
    try { $window.DragMove() } catch { return }
    $settings.Left = [int]$window.Left
    $settings.Top = [int]$window.Top
    $settings | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding utf8
})
$showFrame = {
    $lockButton.Visibility = [System.Windows.Visibility]::Visible
    $mediaControls.Visibility = [System.Windows.Visibility]::Visible
    if (-not $settings.Locked) {
        $frame.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(42, 30, 144, 255))
        $frame.BorderBrush = [System.Windows.Media.Brushes]::DodgerBlue
    }
}
$hideFrame = {
    # A locked overlay must keep its only unlock control reachable.
    if ($settings.Locked) {
        $lockButton.Visibility = [System.Windows.Visibility]::Visible
        $mediaControls.Visibility = [System.Windows.Visibility]::Collapsed
        return
    }
    $lockButton.Visibility = [System.Windows.Visibility]::Collapsed
    $mediaControls.Visibility = [System.Windows.Visibility]::Collapsed
    $frame.Background = [System.Windows.Media.Brushes]::Transparent
    $frame.BorderBrush = [System.Windows.Media.Brushes]::Transparent
}
$lockButton.Add_Click({ $settings.Locked = -not [bool]$settings.Locked; Apply-Settings; & $showFrame })
$window.Add_MouseEnter({ & $showFrame })
$window.Add_MouseLeave({ & $hideFrame })
$caption.Add_MouseEnter({ & $showFrame })
$lockButton.Add_MouseEnter({ & $showFrame })
$lockButton.Add_MouseLeave({ & $hideFrame })
$saveFrame = {
    $settings.Width = [int]$window.Width
    $settings.Height = [int]$window.Height
    $settings.Left = [int]$window.Left
    $settings.Top = [int]$window.Top
    $settings | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding utf8
}
$leftGrip.Add_DragDelta({ param($sender,$event)
    if ($settings.Locked) { return }
    $newWidth = [Math]::Max(260, $window.Width - $event.HorizontalChange)
    $window.Left += $window.Width - $newWidth
    $window.Width = $newWidth
    & $saveFrame
})
$leftGrip.Add_DragStarted({ $script:isAdjusting = $true })
$leftGrip.Add_DragCompleted({ $script:isAdjusting = $false })
$rightGrip.Add_DragDelta({ param($sender,$event)
    if ($settings.Locked) { return }
    $window.Width = [Math]::Max(260, $window.Width + $event.HorizontalChange)
    & $saveFrame
})
$rightGrip.Add_DragStarted({ $script:isAdjusting = $true })
$rightGrip.Add_DragCompleted({ $script:isAdjusting = $false })
$topGrip.Add_DragDelta({ param($sender,$event)
    if ($settings.Locked) { return }
    $script:verticalDrag += $event.VerticalChange
    $window.Height = [Math]::Max(70, $script:verticalStartHeight - $script:verticalDrag)
    $window.Top = $script:verticalStartTop + ($script:verticalStartHeight - $window.Height)
})
$topGrip.Add_DragStarted({ $script:isAdjusting = $true; $script:verticalDrag = 0.0; $script:verticalStartHeight = $window.Height; $script:verticalStartTop = $window.Top; $caption.Opacity = 0 })
$topGrip.Add_DragCompleted({
    $lineHeight = $caption.FontSize * 1.6
    $settings.Lines = [Math]::Max(1, [Math]::Min(5, [Math]::Round(($window.Height - 144) / $lineHeight)))
    $window.Height = [Math]::Max(100, ($lineHeight * [int]$settings.Lines) + 144)
    $window.Top = ($script:verticalStartTop + $script:verticalStartHeight) - $window.Height
    $caption.MaxHeight = $window.Height - 144; $caption.Opacity = 1; $script:isAdjusting = $false
    if ($script:lastRaw) { $caption.Text = Format-Lyrics $script:lastRaw }; & $saveFrame; $script:last = ''
})
$bottomGrip.Add_DragDelta({ param($sender,$event)
    if ($settings.Locked) { return }
    $script:verticalDrag += $event.VerticalChange
    $window.Height = [Math]::Max(70, $script:verticalStartHeight + $script:verticalDrag)
})
$bottomGrip.Add_DragStarted({ $script:isAdjusting = $true; $script:verticalDrag = 0.0; $script:verticalStartHeight = $window.Height; $caption.Opacity = 0 })
$bottomGrip.Add_DragCompleted({
    $lineHeight = $caption.FontSize * 1.6
    $settings.Lines = [Math]::Max(1, [Math]::Min(5, [Math]::Round(($window.Height - 144) / $lineHeight)))
    $window.Height = [Math]::Max(100, ($lineHeight * [int]$settings.Lines) + 144)
    $caption.MaxHeight = $window.Height - 144; $caption.Opacity = 1; $script:isAdjusting = $false
    if ($script:lastRaw) { $caption.Text = Format-Lyrics $script:lastRaw }; & $saveFrame; $script:last = ''
})
$window.Add_SizeChanged({
    if (-not $settings.Locked -and $window.ActualWidth -gt 180) {
        $settings.Width = [int]$window.ActualWidth
        $caption.MaxWidth = [Math]::Max(180, $window.ActualWidth - 56)
        $translationText.MaxWidth = [Math]::Max(180, $window.ActualWidth - 48)
        $settings | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding utf8
    }
})
$captionMenu = New-Object System.Windows.Controls.ContextMenu
$settingsItem = New-Object System.Windows.Controls.MenuItem
$settingsItem.Header = 'Settings'
$settingsItem.Add_Click({ $panel.Show(); $panel.Activate() })
$captionMenu.Items.Add($settingsItem) | Out-Null
$exitItem = New-Object System.Windows.Controls.MenuItem
$exitItem.Header = 'Exit and restore original captions'
$exitItem.Add_Click({ $window.Close() })
$captionMenu.Items.Add($exitItem) | Out-Null
$caption.ContextMenu = $captionMenu
$panel.Add_Closing({ param($sender,$event) $event.Cancel = $true; $panel.Hide() })

function Get-LiveCaptionText {
    if ($QaDemo) { return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5pio5pel44CB5paw44GX44GE44Ky44O844Og44KS6LK344GE44G+44GX44Gf44CC5oCd44Gj44Gf44KI44KK6Zuj44GX44GL44Gj44Gf44GR44Gp44CB5pyA5b6M44G+44Gn44KE44Gj44Gm44G/44Gf44GE44CC')) }
    $process = [System.Diagnostics.Process]::GetProcessesByName('LiveCaptions') | Select-Object -First 1
    if ($null -eq $process) { return '' }

    $handle = [LyricsNative]::FindWindowForProcess($process.Id)
    if ($handle -eq [IntPtr]::Zero) { return '' }

    # Keep the source window alive for UI Automation, but make its own chrome invisible.
    if ($script:preparedHandle -ne $handle) {
        [LyricsNative]::SetCloaked($handle, $false)
        [LyricsNative]::ShowWindowAsync($handle, 4) | Out-Null
        $script:preparedHandle = $handle
    }
    [LyricsNative]::SetWindowPos($handle, [IntPtr]::Zero, -32000, -32000, 0, 0, 0x0015) | Out-Null
    try {
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($handle)
        $condition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
            'CaptionsTextBlock'
        )
        $element = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
        if ($null -eq $element) { return '' }
        return $element.Current.Name
    } catch { return '' }
}

function Format-Lyrics([string]$Text) {
    $clean = ($Text -replace '\s+', ' ').Trim()
    if (-not $clean) { return '' }
    $maxChars = [Math]::Max(16, [int](($window.Width - 56) / ($caption.FontSize * 1.05)) * [int]$settings.Lines)
    $parts = [regex]::Split($clean, '(?<=[\u3002\uFF01\uFF1F.!?])') | Where-Object { $_.Trim() }
    $tail = ($parts | Select-Object -Last 2) -join ''
    if (-not $tail) { $tail = $clean }
    if ($tail.Length -le $maxChars) { return $tail.Trim() }

    $lastPart = [string]($parts | Select-Object -Last 1)
    if ($lastPart -and $lastPart.Trim().Length -le $maxChars) {
        return $lastPart.Trim()
    }

    # Only hard-trim when one unfinished sentence is itself too long to fit.
    $tail = $tail.Substring($tail.Length - $maxChars)
    return $tail.Trim()
}

$script:nextMediaRefresh = [DateTime]::MinValue
function Update-MediaSessionDisplay {
    if ($QaDemo) {
        $mediaTitle.Text = 'Synthetic Player | Release QA Demo | Synthetic Artist'
        $previousButton.IsEnabled = $false
        $toggleButton.IsEnabled = $false
        $nextButton.IsEnabled = $false
        return
    }
    if (-not (Test-Path -LiteralPath $mediaSnapshotPath)) {
        $mediaTitle.Text = '未检测到系统媒体会话'
        $previousButton.IsEnabled = $false
        $toggleButton.IsEnabled = $false
        $nextButton.IsEnabled = $false
        return
    }
    try {
        $media = Get-Content -Raw -Encoding UTF8 -LiteralPath $mediaSnapshotPath | ConvertFrom-Json
        if (-not $media.HasSession) {
            $mediaTitle.Text = '未检测到系统媒体会话'
            $previousButton.IsEnabled = $false
            $toggleButton.IsEnabled = $false
            $nextButton.IsEnabled = $false
            return
        }
        $parts = @([string]$media.AppName, [string]$media.Title) | Where-Object { $_ }
        if ($media.Artist) { $parts += [string]$media.Artist }
        $mediaTitle.Text = $parts -join '  ·  '
        $toggleButton.Content.Text = if ($media.PlaybackStatus -eq 'Playing') { '⏸' } else { '▶' }
        $toggleButton.ToolTip = if ($media.PlaybackStatus -eq 'Playing') { '暂停' } else { '播放' }
        $previousButton.IsEnabled = [bool]$media.CanPrevious
        $toggleButton.IsEnabled = [bool]$media.CanToggle
        $nextButton.IsEnabled = [bool]$media.CanNext
    } catch {
        $mediaTitle.Text = '正在读取系统媒体会话…'
    }
}

$last = ''
$script:lastTranslationSource = ''
$script:translationSequence = 0
$script:lastDisplayedTranslationId = 0
$script:lastCaptionChangedAt = [DateTime]::UtcNow
$script:translationBurstStartedAt = [DateTime]::MinValue
$script:lastTranslationRequestedAt = [DateTime]::MinValue
$script:lastTranslationRequestedId = 0
$script:lastTranslationRequestedText = ''
$script:translationRequests = @{}
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(350)
$timer.Add_Tick({
    if ($script:isAdjusting) { return }
    $now = [DateTime]::UtcNow
    if (-not $QaDemo) {
        $liveCaptionsRunning = $null -ne ([System.Diagnostics.Process]::GetProcessesByName('LiveCaptions') | Select-Object -First 1)
        if (-not $liveCaptionsRunning) {
            $script:preparedHandle = [IntPtr]::Zero
            $script:lastRaw = ''
            $last = ''
            $caption.Text = ''
            $window.Visibility = [System.Windows.Visibility]::Hidden
            return
        }
    }
    if ($now -ge $script:nextMediaRefresh) {
        Update-MediaSessionDisplay
        $script:nextMediaRefresh = $now.AddMilliseconds(650)
    }
    $script:lastRaw = Get-LiveCaptionText
    $next = Format-Lyrics $script:lastRaw
    if ($next -ne $last) {
        $last = $next
        $caption.Text = $next
        $window.Visibility = if ($next) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Hidden }
        $script:lastCaptionChangedAt = $now
        if ($next -and $script:translationBurstStartedAt -eq [DateTime]::MinValue) {
            $script:translationBurstStartedAt = $now
        }
        if (-not $next) {
            $script:translationBurstStartedAt = [DateTime]::MinValue
            $script:lastTranslationSource = ''
        } elseif ($settings.Translate -and $script:lastDisplayedTranslationId -eq 0 -and $script:lastTranslationRequestedId -eq 0) {
            $translationText.Text = '正在捕捉字幕…'
        }
    }

    $hasSentenceBoundary = [bool]($next -match '[\u3002\uFF01\uFF1F.!?…]$')
    $quietDue = $next -and ($now -ge $script:lastCaptionChangedAt.AddMilliseconds(300))
    $forceDue = $next -and $script:translationBurstStartedAt -ne [DateTime]::MinValue -and ($now -ge $script:translationBurstStartedAt.AddMilliseconds(1400))
    $intervalDue = $script:lastTranslationRequestedAt -eq [DateTime]::MinValue -or ($now -ge $script:lastTranslationRequestedAt.AddMilliseconds(700))

    if ($settings.Translate -and $next -and $next -ne $script:lastTranslationSource -and $intervalDue -and ($hasSentenceBoundary -or $quietDue -or $forceDue) -and ((Test-Path -LiteralPath $translationWorkerExe) -or (Test-Path -LiteralPath $translationPythonw))) {
        $script:lastTranslationSource = $next
        $script:translationSequence++
        $script:lastTranslationRequestedId = $script:translationSequence
        $script:lastTranslationRequestedText = $next
        $script:translationRequests[[long]$script:translationSequence] = $next
        $script:lastTranslationRequestedAt = $now
        $script:translationBurstStartedAt = [DateTime]::MinValue
        if ($script:lastDisplayedTranslationId -eq 0) { $translationText.Text = '正在翻译…' }
        try {
            $requestJson = @{ id = $script:translationSequence; text = $next } | ConvertTo-Json -Compress
            $temporaryRequest = $translationRequestPath + '.' + $PID + '.tmp'
            [System.IO.File]::WriteAllText($temporaryRequest, $requestJson, (New-Object System.Text.UTF8Encoding($false)))
            Move-Item -LiteralPath $temporaryRequest -Destination $translationRequestPath -Force
        } catch {
            $script:lastTranslationSource = ''
            $script:lastTranslationRequestedId = 0
            $script:lastTranslationRequestedText = ''
            [void]$script:translationRequests.Remove([long]$script:translationSequence)
            $translationText.Text = '离线翻译请求失败'
        }
    }
    if ($settings.Translate -and (Test-Path -LiteralPath $translationResponsePath)) {
        try {
            $translationResult = Get-Content -Raw -Encoding UTF8 -LiteralPath $translationResponsePath | ConvertFrom-Json
            $responseId = [long]$translationResult.id
            $expectedText = $null
            if ($script:translationRequests.ContainsKey($responseId)) {
                $expectedText = [string]$script:translationRequests[$responseId]
            }
            $freshEnough = $responseId -ge ([long]$script:lastTranslationRequestedId - 1)
            if ($responseId -gt [long]$script:lastDisplayedTranslationId -and $freshEnough -and $expectedText -and [string]$translationResult.text -ceq $expectedText) {
                if ($translationResult.translation) { $translationText.Text = [string]$translationResult.translation }
                elseif ($translationResult.error) { $translationText.Text = [string]$translationResult.error }
                $script:lastDisplayedTranslationId = $responseId
                foreach ($requestId in @($script:translationRequests.Keys)) {
                    if ([long]$requestId -le $responseId) { [void]$script:translationRequests.Remove($requestId) }
                }
            }
        } catch {}
    }
})
$window.Add_Closed({
    $timer.Stop()
    if ($guardTimer) { $guardTimer.Stop() }
    if (-not $QaDemo) { Restore-LiveCaptions }
    $mutex.ReleaseMutex()
    $mutex.Dispose()
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()
})
$timer.Start()
$guardTimer = New-Object System.Windows.Threading.DispatcherTimer
$guardTimer.Interval = [TimeSpan]::FromMilliseconds(50)
$guardTimer.Add_Tick({
    if (-not $QaDemo) {
        $liveCaptionsRunning = $null -ne ([System.Diagnostics.Process]::GetProcessesByName('LiveCaptions') | Select-Object -First 1)
        if (-not $liveCaptionsRunning) {
            $script:preparedHandle = [IntPtr]::Zero
            $script:lastRaw = ''
            $last = ''
            $caption.Text = ''
            $window.Visibility = [System.Windows.Visibility]::Hidden
            return
        }
    }
    if ($script:preparedHandle -and $script:preparedHandle -ne [IntPtr]::Zero) {
        [LyricsNative]::SetWindowPos($script:preparedHandle, [IntPtr]::Zero, -32000, -32000, 0, 0, 0x0015) | Out-Null
    }
})
$guardTimer.Start()
$window.Show()
[System.Windows.Threading.Dispatcher]::Run()
