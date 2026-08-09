param(
    [string]$Profile = 'Night',
    [switch]$DisablePhysicalMonitors,
    [switch]$Lock,
    [switch]$SkipParsecConfig
)

. 'C:\PCMode\remote-common.ps1'

New-PCModeLog -Name 'night-mode-on' | Out-Null
Write-PCModeLog "Starting night mode on, profile=$Profile"

$config = Get-RemoteModeConfig
Save-NightModeState -Profile $Profile | Out-Null
Set-NightModeActiveFlag -Profile $Profile

Set-ComputerStayAwake
Ensure-ParsecService | Out-Null

$virtualAudio = Get-PreferredVirtualAudioEndpoint -Config $config
$localAudio = Get-PreferredLocalAudioEndpoint -Config $config

if ($virtualAudio) {
    Write-PCModeLog "Virtual audio candidate found: $($virtualAudio.Name) [$($virtualAudio.MMDeviceId)]"
} else {
    Write-PCModeLog 'No virtual audio device found; Parsec will use the stable local fallback when available'
}

if ($localAudio) {
    Write-PCModeLog "Stable local audio candidate found: $($localAudio.Name) [$($localAudio.MMDeviceId)]"
}

if (-not $SkipParsecConfig) {
    if ($virtualAudio) {
        Set-DefaultRenderAudioEndpoint -Endpoint $virtualAudio | Out-Null
        if ([bool]$config.ResetPerAppAudioRoutingInNightMode) {
            Reset-AppAudioRouting -Reason "Night mode selected virtual audio for $Profile" | Out-Null
        } else {
            Write-PCModeLog 'Per-app audio routing left untouched for stability'
        }
        $muteValue = if ([bool]$config.KeepHostMutedWithVirtualAudio) { 1 } else { 0 }
        Set-ParsecRemoteConfig -Config $config -ServerAdminMute $muteValue -HostAudioId $virtualAudio.MMDeviceId
    } elseif ($localAudio) {
        Set-DefaultRenderAudioEndpoint -Endpoint $localAudio | Out-Null
        if ([bool]$config.ResetPerAppAudioRoutingInNightMode) {
            Reset-AppAudioRouting -Reason "Night mode selected local audio fallback for $Profile" | Out-Null
        } else {
            Write-PCModeLog 'Per-app audio routing left untouched for stability'
        }
        $muteValue = if ([bool]$config.KeepHostMutedWithoutVirtualAudio) { 1 } else { 0 }
        Set-ParsecRemoteConfig -Config $config -ServerAdminMute $muteValue -HostAudioId $localAudio.MMDeviceId
    } else {
        $muteValue = if ([bool]$config.KeepHostMutedWithoutVirtualAudio) { 1 } else { 0 }
        Set-ParsecRemoteConfig -Config $config -ServerAdminMute $muteValue
    }
} else {
    Write-PCModeLog 'Parsec config update skipped by parameter'
}

if ($DisablePhysicalMonitors -or [bool]$config.AggressiveDisablePhysicalMonitors) {
    if (Test-IsAdmin) {
        Disable-PhysicalMonitors | Out-Null
    } else {
        Write-PCModeLog 'Physical monitor disable requested but skipped because this shell is not admin'
    }
} else {
    Write-PCModeLog 'Aggressive monitor disable is off'
}

$ddcScript = 'C:\PCMode\ddc-monitor-power.ps1'
if ([bool]$config.UseDdcMonitorPowerOff -and (Test-Path -LiteralPath $ddcScript)) {
    Write-PCModeLog 'Requesting DDC monitor sleep; Windows display signal stays active for Parsec'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ddcScript -Action Off *> $null
    $ddcExit = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    Write-PCModeLog "DDC monitor sleep exit=$ddcExit"

    if ($ddcExit -ne 0 -and [bool]$config.UseWindowsDisplayPowerOffFallback) {
        Write-PCModeLog 'DDC monitor sleep failed, falling back to Windows display power-off'
        Invoke-DisplayOff
    }
} elseif ([bool]$config.UseWindowsDisplayPowerOffFallback) {
    Write-PCModeLog 'DDC monitor sleep unavailable, using Windows display power-off fallback'
    Invoke-DisplayOff
} else {
    Write-PCModeLog 'Monitor sleep skipped: DDC disabled and Windows display power-off fallback disabled'
}

if ($Lock -or [bool]$config.LockWorkstationOnNightMode) {
    Write-PCModeLog 'Locking workstation'
    rundll32.exe user32.dll,LockWorkStation
}

Write-PCModeLog 'Night mode on complete'
