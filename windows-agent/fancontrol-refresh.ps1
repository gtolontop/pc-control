param(
    [string]$ProfileName = 'Default',
    [int]$StartupDelaySeconds = 6
)

$ErrorActionPreference = 'Continue'

$BaseDir = 'C:\PCMode'
$LogDir = Join-Path $BaseDir 'logs'
if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$LogPath = Join-Path $LogDir 'last-fancontrol-refresh.log'
"=== FanControl refresh $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -LiteralPath $LogPath -Encoding utf8

function Write-FanControlRefreshLog {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
    $line | Out-File -LiteralPath $LogPath -Append -Encoding utf8
}

$fanControl = 'C:\Program Files (x86)\FanControl\FanControl.exe'
$configPath = "C:\Program Files (x86)\FanControl\Configurations\$ProfileName.json"

if (-not (Test-Path -LiteralPath $fanControl)) {
    Write-FanControlRefreshLog "FanControl.exe missing: $fanControl"
    exit 2
}

if (-not (Test-Path -LiteralPath $configPath)) {
    Write-FanControlRefreshLog "FanControl profile missing: $configPath"
    exit 3
}

$existing = @(Get-Process -Name 'FanControl' -ErrorAction SilentlyContinue)
if ($existing.Count -gt 0) {
    Write-FanControlRefreshLog ("Stopping FanControl instances: {0}" -f ($existing.Id -join ', '))
    foreach ($process in $existing) {
        try {
            Stop-Process -Id $process.Id -Force -ErrorAction Stop
            Write-FanControlRefreshLog "Stop requested for FanControl pid=$($process.Id)"
        } catch {
            Write-FanControlRefreshLog "Could not stop FanControl pid=$($process.Id): $_"
        }
    }
    Start-Sleep -Seconds 3
} else {
    Write-FanControlRefreshLog 'No running FanControl instance found'
}

$stillRunning = @(Get-Process -Name 'FanControl' -ErrorAction SilentlyContinue)
if ($stillRunning.Count -gt 0) {
    Write-FanControlRefreshLog ("FanControl still running before restart: {0}" -f ($stillRunning.Id -join ', '))
}

Write-FanControlRefreshLog ("Starting FanControl profile: {0}.json" -f $ProfileName)
try {
    Start-Process -FilePath $fanControl -ArgumentList @('--config', "$ProfileName.json") -WorkingDirectory (Split-Path -Path $fanControl -Parent) -WindowStyle Hidden -ErrorAction Stop
} catch {
    Write-FanControlRefreshLog "FanControl start failed: $_"
    exit 4
}
Start-Sleep -Seconds $StartupDelaySeconds

$running = @(Get-Process -Name 'FanControl' -ErrorAction SilentlyContinue)
Write-FanControlRefreshLog ("FanControl running instances after refresh: {0}" -f $running.Count)
foreach ($process in $running) {
    Write-FanControlRefreshLog ("FanControl pid={0} started={1}" -f $process.Id, $process.StartTime)
}

if ($running.Count -eq 0) {
    exit 5
}

exit 0
