param(
    [int]$IntervalSeconds = 2
)

. 'C:\PCMode\remote-common.ps1'

New-PCModeLog -Name 'ddc-night-keeper' | Out-Null
Write-PCModeLog "Starting DDC night keeper, interval=$IntervalSeconds seconds"

$lockPath = Join-Path $script:PCModeStateDir 'ddc-night-keeper.lock'
$pidPath = Join-Path $script:PCModeStateDir 'ddc-night-keeper.pid'

try {
    if (Test-Path -LiteralPath $pidPath) {
        $oldPid = [int](Get-Content -LiteralPath $pidPath -Raw -ErrorAction SilentlyContinue)
        if ($oldPid -gt 0) {
            $old = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
            if ($old) {
                Write-PCModeLog "Another DDC night keeper is already running: pid=$oldPid"
                exit 0
            }
        }
    }
} catch {
    Write-PCModeLog "Could not inspect old keeper pid: $_"
}

$PID | Out-File -LiteralPath $pidPath -Encoding ASCII -Force
New-Item -ItemType File -Path $lockPath -Force | Out-Null

$ddcScript = 'C:\PCMode\ddc-monitor-power.ps1'
if (-not (Test-Path -LiteralPath $ddcScript)) {
    Write-PCModeLog "DDC script missing: $ddcScript"
    exit 2
}

try {
    while (Test-NightModeActive) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ddcScript -Action Off *>> $script:CurrentLogPath
        Write-PCModeLog "DDC off refresh exit=$LASTEXITCODE"
        Start-Sleep -Seconds ([Math]::Max(1, $IntervalSeconds))
    }
} finally {
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    Write-PCModeLog 'DDC night keeper stopped because night mode is no longer active'
}
