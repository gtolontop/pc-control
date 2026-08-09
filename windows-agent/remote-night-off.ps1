param(
    [switch]$SkipDdc,
    [switch]$Force
)

. 'C:\PCMode\remote-common.ps1'

New-PCModeLog -Name 'remote-night-off' | Out-Null
Write-PCModeLog 'Starting remote night off'

$wasNightActive = Test-NightModeActive
if (-not $wasNightActive -and -not $Force) {
    Write-PCModeLog 'Remote night is not active; screen wake skipped'
    Ensure-ParsecService | Out-Null
    Write-PCModeLog 'Remote night off complete'
    exit 0
}

if ($SkipDdc) {
    Clear-NightModeActiveFlag
    Ensure-ParsecService | Out-Null
    Restore-SavedDefaultAudioEndpoint | Out-Null
    $config = Get-RemoteModeConfig
    Set-ParsecRemoteConfig -Config $config -ServerAdminMute 0
    Invoke-DisplayWake
    Write-PCModeLog 'Remote night off complete without DDC'
} else {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\PCMode\wake-screens.ps1' *>> $script:CurrentLogPath
    Write-PCModeLog "wake-screens exit=$LASTEXITCODE"
}
