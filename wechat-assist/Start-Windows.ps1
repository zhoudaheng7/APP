param([switch]$Phone, [switch]$Background, [switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$sessionPath = Join-Path $root 'runtime\session.json'
if (Test-Path -LiteralPath $sessionPath) {
    try {
        $session = Get-Content -LiteralPath $sessionPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $adminUri = [Uri]$session.admin_url
        if ($adminUri.Scheme -ne 'http' -or $adminUri.Host -ne '127.0.0.1' -or $adminUri.Port -ne 8765) { throw 'Invalid session address' }
        $null = Get-Process -Id ([int]$session.pid) -ErrorAction Stop
        $token = $adminUri.Fragment.Substring('#token='.Length)
        $state = Invoke-RestMethod -Uri 'http://127.0.0.1:8765/api/state' -Headers @{Authorization=('Bearer '+$token)} -TimeoutSec 3
        if ($null -eq $state.capture) { throw 'Invalid service response' }
        if ($Phone -and -not $session.phone_enabled) { throw '服务当前未启用手机接口，请先停止后重新启动。' }
        if (-not $NoBrowser) { $null = [System.Diagnostics.Process]::Start($session.admin_url) }
        Write-Host '已打开正在运行的知会工作台。'
        exit 0
    } catch { Write-Host '正在检查并启动本机服务。' }
}
$venvPython = Join-Path $root '.venv\Scripts\python.exe'
$runtimePython = $null
$candidates = @($venvPython)
$command = Get-Command python -ErrorAction SilentlyContinue
if ($command -and $command.Source -notmatch '\\WindowsApps\\') { $candidates += $command.Source }
$candidates += (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe')
foreach ($candidate in $candidates) {
    if (-not (Test-Path -LiteralPath $candidate)) { continue }
    & $candidate -c "import sys; sys.exit(0 if sys.version_info >= (3,11) else 1)" 2>$null
    if ($LASTEXITCODE -eq 0) { $runtimePython = $candidate; break }
}
if (-not $runtimePython) { throw '未找到 Python 3.11+。请安装 Python 并启用 PATH，再重新运行。' }
& $runtimePython -c "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('cryptography') else 1)"
if ($LASTEXITCODE -ne 0) {
    Write-Host '首次运行将在工具目录内建立虚拟环境并安装必要组件。'
    if ($runtimePython -ne $venvPython) {
        & $runtimePython -m venv (Join-Path $root '.venv')
        if ($LASTEXITCODE -ne 0) { throw '无法建立 Python 虚拟环境。' }
    }
    & $venvPython -m pip install -r (Join-Path $root 'requirements.txt')
    if ($LASTEXITCODE -ne 0) { throw '依赖安装失败，请检查网络后重试。' }
    $runtimePython = $venvPython
}
$server = Join-Path $root 'bridge\server.py'
$serverArgs = @($server)
if ($Phone) { $serverArgs += '--lan' }
if ($NoBrowser) { $serverArgs += '--no-browser' }
if ($Background) {
    $runtimeDir = Join-Path $root 'runtime'
    $null = New-Item -ItemType Directory -Path $runtimeDir -Force
    $quotedArgs = @('"'+$server+'"')
    if ($serverArgs.Count -gt 1) { $quotedArgs += $serverArgs[1..($serverArgs.Count-1)] }
    $process = Start-Process -FilePath $runtimePython -ArgumentList $quotedArgs -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtimeDir 'service.stdout.log') -RedirectStandardError (Join-Path $runtimeDir 'service.stderr.log')
    for ($attempt=0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Milliseconds 200
        if ($process.HasExited) { throw ('服务启动失败，请查看 '+(Join-Path $runtimeDir 'service.stderr.log')) }
        if (Test-Path -LiteralPath $sessionPath) {
            $newSession = Get-Content -LiteralPath $sessionPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([int]$newSession.pid -eq $process.Id) {
                Write-Host '知会已在后台启动。再次双击 Start-Windows.cmd 可重新打开工作台。'
                exit 0
            }
        }
    }
    throw '服务启动超时，请查看 runtime 中的日志。'
} else {
    & $runtimePython @serverArgs
}
