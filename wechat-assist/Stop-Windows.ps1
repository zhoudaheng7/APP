$ErrorActionPreference = 'Stop'
$sessionPath = Join-Path $PSScriptRoot 'runtime\session.json'
if (-not (Test-Path -LiteralPath $sessionPath)) { Write-Host '知会当前没有运行。'; exit 0 }
$session = Get-Content -LiteralPath $sessionPath -Raw -Encoding UTF8 | ConvertFrom-Json
$uri = [Uri]$session.admin_url
if ($uri.Scheme -ne 'http' -or $uri.Host -ne '127.0.0.1' -or $uri.Port -ne 8765) { throw '运行信息无效。' }
$token = $uri.Fragment.Substring('#token='.Length)
$null = Invoke-RestMethod -Uri 'http://127.0.0.1:8765/api/shutdown' -Method Post -ContentType 'application/json' -Body '{}' -Headers @{Authorization=('Bearer '+$token)} -TimeoutSec 3
Write-Host '知会服务已停止。未保存的识别文字和草稿会清空。'
