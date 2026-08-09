$ErrorActionPreference = 'Continue'

$mode = 'Perf'
$requestFile = Join-Path $env:LOCALAPPDATA 'PCMode\requested-mode.txt'
$validModes = @('Perf', 'Normal', 'Chill', 'Sleep', 'SleepServer', 'SleepHeavy', 'RemoteNight', 'RemoteNightGpu', 'Status', 'KeyboardReset', 'AudioServiceReset', 'ParsecRepair', 'ParsecConfigApply', 'InstallRemoteTasks', 'StartNightWatchdog', 'NightOff', 'WakeScreens', 'DisplayRecover', 'GpuDisplayRecover', 'ResetDisplayRegistry', 'PhysicalDisplayRecover', 'DisableNightWatchdog', 'RgbOff')

if (Test-Path -Path $requestFile) {
    $requested = (Get-Content -Path $requestFile -Raw -ErrorAction SilentlyContinue).Trim()
    Remove-Item -Path $requestFile -Force -ErrorAction SilentlyContinue
    if ($validModes -contains $requested) {
        $mode = $requested
    }
}

if ($mode -eq 'AudioServiceReset') {
    Stop-Process -Name audiodg -Force -ErrorAction SilentlyContinue
    Restart-Service -Name Audiosrv -Force -ErrorAction SilentlyContinue
    Restart-Service -Name AudioEndpointBuilder -Force -ErrorAction SilentlyContinue
    Start-Service -Name AudioEndpointBuilder -ErrorAction SilentlyContinue
    Start-Service -Name Audiosrv -ErrorAction SilentlyContinue
    & 'C:\PCMode\local-rescue.ps1' -SkipScreenWake -TargetVolumePercent 50
    exit $LASTEXITCODE
}

if ($mode -eq 'RgbOff') {
    & 'C:\PCMode\rgb-off.ps1'
    exit $LASTEXITCODE
}

if ($mode -eq 'ParsecRepair') {
    & 'C:\PCMode\parsec-repair.ps1' -RestartParsec
    exit $LASTEXITCODE
}

if ($mode -eq 'ParsecConfigApply') {
    & 'C:\PCMode\parsec-repair.ps1'
    exit $LASTEXITCODE
}

if ($mode -eq 'InstallRemoteTasks') {
    & 'C:\PCMode\install-remote-tasks.ps1'
    exit $LASTEXITCODE
}

if ($mode -eq 'StartNightWatchdog') {
    # Disabled by default: hard monitor toggling causes Parsec capture freezes on this setup.
    exit 0
}

if ($mode -eq 'NightOff') {
    & 'C:\PCMode\night-mode-off.ps1'
    exit $LASTEXITCODE
}

if ($mode -eq 'WakeScreens') {
    & 'C:\PCMode\wake-screens.ps1'
    exit $LASTEXITCODE
}

if ($mode -eq 'DisplayRecover') {
    & 'C:\PCMode\display-recover.ps1'
    exit $LASTEXITCODE
}

if ($mode -eq 'GpuDisplayRecover') {
    & 'C:\PCMode\gpu-display-recover.ps1'
    exit $LASTEXITCODE
}

if ($mode -eq 'ResetDisplayRegistry') {
    & 'C:\PCMode\reset-display-registry.ps1'
    exit $LASTEXITCODE
}

if ($mode -eq 'PhysicalDisplayRecover') {
    & 'C:\PCMode\physical-display-recover.ps1'
    exit $LASTEXITCODE
}

if ($mode -eq 'DisableNightWatchdog') {
    Stop-ScheduledTask -TaskName 'PCMode_Night_Watchdog_Logon' -ErrorAction SilentlyContinue
    Disable-ScheduledTask -TaskName 'PCMode_Night_Watchdog_Logon' -ErrorAction SilentlyContinue | Out-Null
    Unregister-ScheduledTask -TaskName 'PCMode_Night_Watchdog_Logon' -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName 'PCMode_Night_Watchdog_Startup' -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath 'C:\PCMode\state\night-mode-active.flag' -Force -ErrorAction SilentlyContinue
    exit 0
}

& 'C:\PCMode\pcmode.ps1' -Mode $mode
exit $LASTEXITCODE
