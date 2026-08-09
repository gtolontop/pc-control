param(
    [switch]$RestoreNormalPowerPlan,
    [switch]$SkipParsecConfig
)

. 'C:\PCMode\remote-common.ps1'

New-PCModeLog -Name 'night-mode-off' | Out-Null
Write-PCModeLog 'Starting night mode off'

$config = Get-RemoteModeConfig
Clear-NightModeActiveFlag

Ensure-ParsecService | Out-Null
Restore-SavedDefaultAudioEndpoint | Out-Null

if (-not $SkipParsecConfig) {
    $virtualAudio = Get-PreferredVirtualAudioEndpoint -Config $config
    $localAudio = Get-PreferredLocalAudioEndpoint -Config $config
    if ($virtualAudio) {
        Write-PCModeLog "Virtual audio candidate found for Parsec capture: $($virtualAudio.Name) [$($virtualAudio.MMDeviceId)]"
        Write-PCModeLog 'Night mode off leaves the Windows default audio endpoint on the restored local device'
        Set-ParsecRemoteConfig -Config $config -ServerAdminMute 0
    } elseif ($localAudio) {
        Write-PCModeLog "Stable local audio candidate found for Parsec capture: $($localAudio.Name) [$($localAudio.MMDeviceId)]"
        Write-PCModeLog 'Night mode off leaves the Windows default audio endpoint on the restored local device'
        Set-ParsecRemoteConfig -Config $config -ServerAdminMute 0
    } else {
        Write-PCModeLog 'No preferred audio endpoint found; Parsec will keep its current/default host audio device'
        Set-ParsecRemoteConfig -Config $config -ServerAdminMute 0
    }
}

if (Test-IsAdmin) {
    Enable-PhysicalMonitors
} else {
    Write-PCModeLog 'Physical monitor enable skipped because this shell is not admin'
    Write-PCModeLog 'Run C:\PCMode\rollback-remote-setup.ps1 as admin if a monitor was disabled'
}

$ddcScript = 'C:\PCMode\ddc-monitor-power.ps1'
if ([bool]$config.UseDdcMonitorPowerOff -and (Test-Path -LiteralPath $ddcScript)) {
    Write-PCModeLog 'Requesting DDC monitor wake'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ddcScript -Action On *> $null
    $ddcExit = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    Write-PCModeLog "DDC monitor wake exit=$ddcExit"
}

Invoke-DisplayWake

if ($RestoreNormalPowerPlan) {
    & powercfg.exe /setactive 381b4222-f694-41f0-9685-ff5bb260df2e *>> $script:CurrentLogPath
    Write-PCModeLog "Restored Balanced power plan exit=$LASTEXITCODE"
}

Write-PCModeLog 'Night mode off complete'
