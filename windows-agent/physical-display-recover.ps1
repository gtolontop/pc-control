$ErrorActionPreference = 'Continue'

. 'C:\PCMode\remote-common.ps1'

New-PCModeLog -Name 'physical-display-recover' | Out-Null
Write-PCModeLog 'Starting physical display recovery'

function Invoke-PhysicalRecoverCommand {
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

$parsecVda = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -match 'Parsec Virtual Display' } |
    Select-Object -First 1

if ($parsecVda) {
    Write-PCModeLog ("Disabling Parsec VDA: {0}" -f $parsecVda.InstanceId)
    Disable-PnpDevice -InstanceId $parsecVda.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}

$nvidia = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -match 'NVIDIA' } |
    Select-Object -First 1

if ($nvidia) {
    Write-PCModeLog ("Restarting NVIDIA adapter: {0}" -f $nvidia.InstanceId)
    Invoke-PhysicalRecoverCommand -FilePath 'pnputil.exe' -ArgumentList @('/restart-device', $nvidia.InstanceId) -Label 'NVIDIA adapter restart' | Out-Null
    Start-Sleep -Seconds 8
}

Invoke-PhysicalRecoverCommand -FilePath 'pnputil.exe' -ArgumentList @('/scan-devices') -Label 'pnputil scan' | Out-Null
Start-Sleep -Seconds 3
Invoke-PhysicalRecoverCommand -FilePath 'DisplaySwitch.exe' -ArgumentList @('/extend') -Label 'display extend' | Out-Null
Start-Sleep -Seconds 2
Invoke-DisplayWake

Write-PCModeLog 'Physical display recovery complete'
