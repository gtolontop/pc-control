. 'C:\PCMode\remote-common.ps1'

New-PCModeLog -Name 'wake-screens' | Out-Null
Write-PCModeLog 'Starting screen wake recovery'

Clear-NightModeActiveFlag
Ensure-ParsecService | Out-Null
Restore-SavedDefaultAudioEndpoint | Out-Null

$config = Get-RemoteModeConfig
Set-ParsecRemoteConfig -Config $config -ServerAdminMute 0

function Set-LocalWakePowerProfile {
    $balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
    $commands = @(
        @('/setactive', $balanced),
        @('/setacvalueindex', 'SCHEME_CURRENT', 'SUB_PROCESSOR', 'PROCTHROTTLEMAX', '80'),
        @('/setacvalueindex', 'SCHEME_CURRENT', 'SUB_PROCESSOR', 'PROCTHROTTLEMIN', '5'),
        @('/setacvalueindex', 'SCHEME_CURRENT', 'SUB_PROCESSOR', 'be337238-0d82-4146-a960-4f3749d470c7', '2'),
        @('/setacvalueindex', 'SCHEME_CURRENT', 'SUB_PROCESSOR', '36687f9e-e3a5-4dbf-b1dc-15eb381c6863', '70'),
        @('/setacvalueindex', 'SCHEME_CURRENT', 'SUB_PROCESSOR', '0cc5b647-c1df-4637-891a-dec35c318583', '50'),
        @('/setacvalueindex', 'SCHEME_CURRENT', '501a4d13-42af-4429-9fd1-a8218c268e20', 'ee12f906-d277-404b-b6da-e5fa1a576df5', '0'),
        @('/setacvalueindex', 'SCHEME_CURRENT', '2a737441-1930-4402-8d77-b2bebba308a3', '48e6b7a6-50f5-4782-a5d4-53bb8f07e226', '0'),
        @('/setacvalueindex', 'SCHEME_CURRENT', '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1', '12bbebe6-58d6-4636-95bb-3217ef867c1a', '0'),
        @('/setactive', 'SCHEME_CURRENT')
    )

    foreach ($args in $commands) {
        & powercfg.exe @args *>> $script:CurrentLogPath
        Write-PCModeLog "powercfg $($args -join ' ') exit=$LASTEXITCODE"
    }

    Write-PCModeLog 'Local wake power profile applied: Balanced chill, USB/PCIe audio-safe'
}

Set-LocalWakePowerProfile

function Invoke-WakeCommand {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$Label
    )

    Write-PCModeLog ("RUN {0}: {1} {2}" -f $Label, $FilePath, ($ArgumentList -join ' '))
    try {
        & $FilePath @ArgumentList *>> $script:CurrentLogPath
        $code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
        Write-PCModeLog ("EXIT {0}: {1}" -f $Label, $code)
        return [int]$code
    } catch {
        Write-PCModeLog ("ERROR {0}: {1}" -f $Label, $_)
        return 999
    }
}

$ddcScript = 'C:\PCMode\ddc-monitor-power.ps1'
if (Test-Path -LiteralPath $ddcScript) {
    Write-PCModeLog 'Requesting DDC monitor on'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ddcScript -Action On *>> $script:CurrentLogPath
    Write-PCModeLog "DDC monitor on exit=$LASTEXITCODE"
} else {
    Write-PCModeLog 'DDC monitor power script missing'
}

Start-Sleep -Seconds 2
Invoke-WakeCommand -FilePath 'DisplaySwitch.exe' -ArgumentList @('/extend') -Label 'display extend before GPU wake' | Out-Null

Invoke-DisplayWake

if (Test-IsAdmin) {
    $nvidia = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match 'NVIDIA' } |
        Select-Object -First 1

    if ($nvidia) {
        Write-PCModeLog "Restarting NVIDIA adapter to wake DDC-off monitors: $($nvidia.InstanceId)"
        Invoke-WakeCommand -FilePath 'pnputil.exe' -ArgumentList @('/restart-device', $nvidia.InstanceId) -Label 'NVIDIA adapter restart' | Out-Null
        Start-Sleep -Seconds 8
        Invoke-WakeCommand -FilePath 'pnputil.exe' -ArgumentList @('/scan-devices') -Label 'pnputil scan' | Out-Null
        Start-Sleep -Seconds 3
        Invoke-WakeCommand -FilePath 'DisplaySwitch.exe' -ArgumentList @('/extend') -Label 'display extend after GPU wake' | Out-Null
        Start-Sleep -Seconds 2

        if (Test-Path -LiteralPath $ddcScript) {
            Write-PCModeLog 'Sending final DDC monitor on after GPU restart'
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ddcScript -Action On *>> $script:CurrentLogPath
            Write-PCModeLog "Final DDC monitor on exit=$LASTEXITCODE"
        }

        Invoke-DisplayWake
    } else {
        Write-PCModeLog 'NVIDIA adapter not found; GPU wake skipped'
    }
} else {
    Write-PCModeLog 'GPU wake skipped because this shell is not admin'
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\PCMode\local-rescue.ps1' -SkipScreenWake -TargetVolumePercent 50 *>> $script:CurrentLogPath
Write-PCModeLog "Local audio rescue exit=$LASTEXITCODE"

$fanControlRefreshScript = 'C:\PCMode\fancontrol-refresh.ps1'
if (Test-Path -LiteralPath $fanControlRefreshScript) {
    Write-PCModeLog 'Refreshing FanControl after GPU/display wake'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fanControlRefreshScript -ProfileName 'Default' *>> $script:CurrentLogPath
    Write-PCModeLog "FanControl refresh exit=$LASTEXITCODE"
} else {
    Write-PCModeLog 'FanControl refresh skipped, script missing'
}

Write-PCModeLog 'Screen wake recovery complete'
