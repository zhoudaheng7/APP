param([switch]$Phone)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$venvPython = Join-Path $root '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $venvPython)) {
    Write-Host '首次运行需要 Python 3.11+。将只在本工具目录建立虚拟环境。'
    python -m venv (Join-Path $root '.venv')
    if ($LASTEXITCODE -ne 0) { throw '请先安装 Python 3.11+，并启用 PATH，然后重试。' }
    & $venvPython -m pip install -r (Join-Path $root 'requirements.txt')
    if ($LASTEXITCODE -ne 0) { throw '依赖安装失败，请检查网络后重试。' }
}
$server = Join-Path $root 'bridge\server.py'
if ($Phone) { & $venvPython $server --lan } else { & $venvPython $server }
