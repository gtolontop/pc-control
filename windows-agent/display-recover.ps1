$ErrorActionPreference = 'Continue'

. 'C:\PCMode\remote-common.ps1'

New-PCModeLog -Name 'display-recover' | Out-Null
Write-PCModeLog 'Starting display recovery'

function Invoke-RecoverCommand {
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
    Write-PCModeLog 'Sending initial DDC wake'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ddcScript -Action On *> $null
    Write-PCModeLog "Initial DDC wake exit=$LASTEXITCODE"
}

Invoke-RecoverCommand -FilePath 'DisplaySwitch.exe' -ArgumentList @('/extend') -Label 'display extend' | Out-Null
Start-Sleep -Seconds 2

Invoke-RecoverCommand -FilePath 'pnputil.exe' -ArgumentList @('/scan-devices') -Label 'pnputil scan' | Out-Null
Start-Sleep -Seconds 3

$monitorDevices = @(Get-PnpDevice -Class Monitor -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -match '^DISPLAY\\' } |
    Sort-Object { if ($_.Status -eq 'OK') { 0 } else { 1 } }, FriendlyName, InstanceId)

foreach ($device in $monitorDevices) {
    Write-PCModeLog ("Monitor device: {0} status={1} id={2}" -f $device.FriendlyName, $device.Status, $device.InstanceId)
}

foreach ($device in $monitorDevices) {
    Invoke-RecoverCommand -FilePath 'pnputil.exe' -ArgumentList @('/restart-device', $device.InstanceId) -Label 'monitor restart' | Out-Null
    Start-Sleep -Seconds 1
}

Invoke-RecoverCommand -FilePath 'DisplaySwitch.exe' -ArgumentList @('/extend') -Label 'display extend after restart' | Out-Null
Start-Sleep -Seconds 2

Invoke-DisplayWake

if (Test-Path -LiteralPath $ddcScript) {
    Write-PCModeLog 'Sending final DDC wake'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ddcScript -Action On *> $null
    Write-PCModeLog "Final DDC wake exit=$LASTEXITCODE"
}

Write-PCModeLog 'Display recovery complete'
