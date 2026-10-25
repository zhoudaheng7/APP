param([switch]$Phone)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
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
& $runtimePython -c "import cryptography" 2>$null
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
if ($Phone) { & $runtimePython $server --lan } else { & $runtimePython $server }
