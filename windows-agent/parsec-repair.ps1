param(
    [switch]$RestartParsec,
    [switch]$SkipConfig
)

. 'C:\PCMode\remote-common.ps1'

New-PCModeLog -Name 'parsec-repair' | Out-Null
Write-PCModeLog 'Starting Parsec repair/keep-alive'

$config = Get-RemoteModeConfig

if ($RestartParsec) {
    Write-PCModeLog 'RestartParsec requested; stopping Parsec before writing config so it cannot rewrite old settings'
    try {
        $service = Get-Service -Name Parsec -ErrorAction Stop
        if ($service.StartType -ne 'Automatic') {
            Set-Service -Name Parsec -StartupType Automatic -ErrorAction SilentlyContinue
        }
        if ($service.Status -ne 'Stopped') {
            Stop-Service -Name Parsec -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
            Write-PCModeLog 'Parsec service stopped'
        }
    } catch {
        Write-PCModeLog "Could not stop Parsec before config write: $_"
    }
} else {
    Ensure-ParsecService | Out-Null
}

Set-ComputerStayAwake

if (-not $SkipConfig) {
    $isNightActive = Test-NightModeActive
    $virtualAudio = Get-PreferredVirtualAudioEndpoint -Config $config
    $localAudio = Get-PreferredLocalAudioEndpoint -Config $config
    if ($virtualAudio) {
        Write-PCModeLog "Virtual audio candidate found for Parsec capture: $($virtualAudio.Name) [$($virtualAudio.MMDeviceId)]"
        Write-PCModeLog 'Parsec repair leaves the Windows default audio endpoint untouched'
        $muteValue = if ($isNightActive -and [bool]$config.KeepHostMutedWithVirtualAudio) { 1 } else { 0 }
        if ($isNightActive) {
            Set-ParsecRemoteConfig -Config $config -ServerAdminMute $muteValue -HostAudioId $virtualAudio.MMDeviceId
        } else {
            Set-ParsecRemoteConfig -Config $config -ServerAdminMute 0
        }
    } elseif ($localAudio) {
        Write-PCModeLog "Stable local audio candidate found for Parsec capture: $($localAudio.Name) [$($localAudio.MMDeviceId)]"
        Write-PCModeLog 'Parsec repair leaves the Windows default audio endpoint untouched'
        $muteValue = if ($isNightActive -and [bool]$config.KeepHostMutedWithoutVirtualAudio) { 1 } else { 0 }
        if ($isNightActive) {
            Set-ParsecRemoteConfig -Config $config -ServerAdminMute $muteValue -HostAudioId $localAudio.MMDeviceId
        } else {
            Set-ParsecRemoteConfig -Config $config -ServerAdminMute 0
        }
    } else {
        Write-PCModeLog 'No preferred audio endpoint found; Parsec will keep its current/default host audio device'
        $muteValue = if ($isNightActive -and [bool]$config.KeepHostMutedWithoutVirtualAudio) { 1 } else { 0 }
        Set-ParsecRemoteConfig -Config $config -ServerAdminMute $muteValue
    }
}

if ($RestartParsec) {
    try {
        Start-Service -Name Parsec -ErrorAction Stop
        Write-PCModeLog 'Parsec service started after config write'
    } catch {
        Write-PCModeLog "Could not start Parsec service after config write: $_"
    }
} else {
    Write-PCModeLog 'Parsec restart skipped to avoid dropping active remote sessions'
}

if (Test-NightModeActive) {
    $keeperScript = 'C:\PCMode\ddc-night-keeper.ps1'
    if (Test-Path -LiteralPath $keeperScript) {
        Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $keeperScript, '-IntervalSeconds', '2') -WindowStyle Hidden
        Write-PCModeLog 'Night mode is active; DDC night keeper requested'
    } else {
        Write-PCModeLog 'Night mode is active but DDC night keeper script is missing'
    }
}

Write-PCModeLog 'Parsec repair complete'
