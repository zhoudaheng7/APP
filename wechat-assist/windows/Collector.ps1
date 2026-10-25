param(
    [ValidateSet('Pick','Watch','OcrFile')] [string]$Mode = 'Watch',
    [string]$ConfigPath,
    [string]$ImagePath
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
$null = [Windows.Storage.Streams.IRandomAccessStream,Windows.Storage.Streams,ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.SoftwareBitmap,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime]
$null = [Windows.Media.Ocr.OcrResult,Windows.Foundation,ContentType=WindowsRuntime]
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class AssistWindow {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left,Top,Right,Bottom; }
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@
$null = [AssistWindow]::SetProcessDPIAware()
$script:asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetGenericArguments().Count -eq 1 -and
    $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1
function Wait-WinRT($Operation, [Type]$Type) {
    $task = $script:asTask.MakeGenericMethod($Type).Invoke($null, @($Operation))
    $task.Wait()
    return $task.Result
}
$script:engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if ($null -eq $script:engine) { throw 'Windows OCR language is unavailable' }
function Read-Bitmap($Image) {
    $memory = New-Object System.IO.MemoryStream
    $Image.Save($memory,[System.Drawing.Imaging.ImageFormat]::Png)
    $memory.Position = 0
    $stream = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($memory)
    $bitmap = $null
    try {
        $decoder = Wait-WinRT ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $bitmap = Wait-WinRT ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        $result = Wait-WinRT ($script:engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
        return (($result.Lines | ForEach-Object { $_.Text }) -join "`n")
    } finally {
        if ($bitmap) { $bitmap.Dispose() }
        $stream.Dispose()
        $memory.Dispose()
    }
}
function Read-Region($r) {
    $image = New-Object System.Drawing.Bitmap([int]$r.w, [int]$r.h)
    $graphics = [System.Drawing.Graphics]::FromImage($image)
    try {
        $graphics.CopyFromScreen([int]$r.x,[int]$r.y,0,0,$image.Size)
        return Read-Bitmap $image
    } finally {
        $graphics.Dispose(); $image.Dispose()
    }
}
function Emit($value) { [Console]::WriteLine(($value | ConvertTo-Json -Compress -Depth 8)) }
function Get-WeChat {
    $candidates = @(Get-Process Weixin,WeChat -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 })
    if ($candidates.Count -ne 1) { throw 'Please keep exactly one WeChat main window open' }
    return $candidates[0]
}
function Select-Region([string]$Prompt) {
    $script:selected = $null
    $script:start = $null
    $script:dragRect = [System.Drawing.Rectangle]::Empty
    $area = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'; $form.TopMost = $true; $form.KeyPreview = $true
    $form.StartPosition = 'Manual'; $form.Bounds = $area
    $form.BackColor = [System.Drawing.Color]::Black; $form.Opacity = 0.40
    $form.Cursor = [System.Windows.Forms.Cursors]::Cross
    $form.Add_Paint({
        param($sender,$e)
        $font = New-Object System.Drawing.Font('Microsoft YaHei',18)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::Lime,3)
        try {
            $e.Graphics.DrawString($Prompt,$font,[System.Drawing.Brushes]::White,30,30)
            $e.Graphics.DrawRectangle($pen,$script:dragRect)
        } finally { $font.Dispose(); $pen.Dispose() }
    })
    $form.Add_MouseDown({ param($sender,$e) $script:start = $e.Location })
    $form.Add_MouseMove({
        param($sender,$e)
        if ($script:start) {
            $script:dragRect = New-Object System.Drawing.Rectangle(
                [Math]::Min($e.X,$script:start.X),[Math]::Min($e.Y,$script:start.Y),
                [Math]::Abs($e.X-$script:start.X),[Math]::Abs($e.Y-$script:start.Y))
            $sender.Invalidate()
        }
    })
    $form.Add_MouseUp({
        param($sender,$e)
        if ($script:dragRect.Width -ge 20 -and $script:dragRect.Height -ge 15) {
            $script:selected = @{ x=$script:dragRect.X+$area.X; y=$script:dragRect.Y+$area.Y;
                                  w=$script:dragRect.Width; h=$script:dragRect.Height }
            $sender.Close()
        }
    })
    $form.Add_KeyDown({ param($sender,$e) if ($e.KeyCode -eq 'Escape') { $sender.Close() } })
    $null = $form.ShowDialog(); $form.Dispose()
    if (-not $script:selected) { throw 'Selection cancelled' }
    return $script:selected
}
function Inside($region,$bounds) {
    return ($region.x -ge $bounds.Left -and $region.y -ge $bounds.Top -and
            ($region.x+$region.w) -le $bounds.Right -and ($region.y+$region.h) -le $bounds.Bottom)
}
if ($Mode -eq 'OcrFile') {
    $image = New-Object System.Drawing.Bitmap([System.IO.Path]::GetFullPath($ImagePath))
    try { Emit @{text=(Read-Bitmap $image); language=$script:engine.RecognizerLanguage.LanguageTag} }
    finally { $image.Dispose() }
    exit 0
}
if ($Mode -eq 'Pick') {
    $wx = Get-WeChat
    if ([AssistWindow]::IsIconic($wx.MainWindowHandle)) { throw 'Restore WeChat before selecting regions' }
    $null = [AssistWindow]::SetForegroundWindow($wx.MainWindowHandle)
    Start-Sleep -Milliseconds 400
    $bounds = New-Object AssistWindow+RECT
    $null = [AssistWindow]::GetWindowRect($wx.MainWindowHandle,[ref]$bounds)
    $header = Select-Region '第一步：圈选顶部聊天名称，只选名称文字。按 Esc 取消。'
    Start-Sleep -Milliseconds 300
    $body = Select-Region '第二步：圈选消息内容区域，不含左侧联系人、聊天标题和输入框。'
    if (-not (Inside $header $bounds) -or -not (Inside $body $bounds)) { throw 'Regions must be inside WeChat' }
    if ($header.w -gt 2600 -or $header.h -gt 2600 -or $body.w -gt 2600 -or $body.h -gt 2600) { throw 'Region exceeds OCR limit' }
    Start-Sleep -Milliseconds 400
    $name = Read-Region $header
    if (-not $name.Trim()) { throw 'Chat title could not be recognized' }
    $cfg = @{ hwnd=$wx.MainWindowHandle.ToInt64(); process_id=$wx.Id; header=$header; body=$body;
              expected_chat=$name.Trim(); bounds=@{Left=$bounds.Left;Top=$bounds.Top;Right=$bounds.Right;Bottom=$bounds.Bottom} }
    $cfg | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
    Emit @{status='ready'; title=$name.Trim()}
    exit 0
}
$cfg = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$handle = [IntPtr]([long]$cfg.hwnd)
while ($true) {
    try {
        $wx = Get-WeChat
        if ($wx.MainWindowHandle -ne $handle -or $wx.Id -ne $cfg.process_id) { throw 'WeChat window changed; select regions again' }
        $bounds = New-Object AssistWindow+RECT
        $null = [AssistWindow]::GetWindowRect($handle,[ref]$bounds)
        if ([AssistWindow]::IsIconic($handle) -or [AssistWindow]::GetForegroundWindow() -ne $handle) {
            Emit @{status='paused'; message='微信未在前台，已暂停屏幕读取'}
        } elseif ($bounds.Left -ne $cfg.bounds.Left -or $bounds.Top -ne $cfg.bounds.Top -or
                  $bounds.Right -ne $cfg.bounds.Right -or $bounds.Bottom -ne $cfg.bounds.Bottom) {
            Emit @{status='paused'; message='微信窗口位置或大小已变化，请重新选择区域'}
        } else {
            $header = Read-Region $cfg.header
            if (($header -replace '\s','') -ne ($cfg.expected_chat -replace '\s','')) {
                Emit @{status='paused'; message='聊天标题不匹配，已暂停；请回到指定聊天'}
            } else {
                $body = Read-Region $cfg.body
                # Re-check foreground and header after OCR so a mid-capture chat switch is rejected.
                $afterHeader = Read-Region $cfg.header
                if ([AssistWindow]::GetForegroundWindow() -eq $handle -and
                    ($afterHeader -replace '\s','') -eq ($cfg.expected_chat -replace '\s','')) {
                    Emit @{status='reading'; header=$header; body=$body}
                } else { Emit @{status='paused'; message='识别期间窗口变化，本次结果已丢弃'} }
            }
        }
    } catch {
        Emit @{status='error'; message='无法读取，请检查微信窗口和 Windows OCR 后重新选择区域'}
    }
    Start-Sleep -Seconds 2
}
