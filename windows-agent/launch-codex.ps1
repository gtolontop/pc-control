$ErrorActionPreference = 'Continue'

$logDir = 'C:\PCMode\logs'
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$logPath = Join-Path $logDir 'last-launch-codex.log'
"=== launch-codex $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -LiteralPath $logPath -Encoding UTF8

function Write-LaunchLog {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
    $line | Out-File -LiteralPath $logPath -Append -Encoding UTF8
}

$running = @(Get-Process -Name 'Codex' -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    Write-LaunchLog "Codex already running, instances=$($running.Count)"
    exit 0
}

$appId = 'OpenAI.Codex_2p2nqsd0c76g0!App'
try {
    Start-Process -FilePath 'explorer.exe' -ArgumentList "shell:AppsFolder\$appId"
    Write-LaunchLog "Codex launch requested through app id: $appId"
} catch {
    Write-LaunchLog "Codex app-id launch failed: $_"

    $fallback = Get-ChildItem -LiteralPath 'C:\Program Files\WindowsApps' -Directory -Filter 'OpenAI.Codex_*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1

    if ($fallback) {
        $exe = Join-Path $fallback.FullName 'app\Codex.exe'
        if (Test-Path -LiteralPath $exe) {
            Start-Process -FilePath $exe -WindowStyle Hidden
            Write-LaunchLog "Codex launch requested through fallback exe: $exe"
        } else {
            Write-LaunchLog "Codex fallback exe missing: $exe"
        }
    } else {
        Write-LaunchLog 'Codex package not found in WindowsApps'
    }
}
