$ErrorActionPreference = 'Continue'

. 'C:\PCMode\remote-common.ps1'

New-PCModeLog -Name 'gpu-display-recover' | Out-Null
Write-PCModeLog 'Starting GPU display recovery'

function Invoke-GpuRecoverCommand {
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

$nvidia = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -match 'NVIDIA' } |
    Select-Object -First 1

if (-not $nvidia) {
    Write-PCModeLog 'No NVIDIA display adapter found'
    exit 2
}

Write-PCModeLog ("NVIDIA adapter: {0} status={1} id={2}" -f $nvidia.FriendlyName, $nvidia.Status, $nvidia.InstanceId)

Invoke-GpuRecoverCommand -FilePath 'DisplaySwitch.exe' -ArgumentList @('/extend') -Label 'display extend before GPU restart' | Out-Null
Start-Sleep -Seconds 2

Invoke-GpuRecoverCommand -FilePath 'pnputil.exe' -ArgumentList @('/restart-device', $nvidia.InstanceId) -Label 'NVIDIA adapter restart' | Out-Null
Start-Sleep -Seconds 8

Invoke-GpuRecoverCommand -FilePath 'pnputil.exe' -ArgumentList @('/scan-devices') -Label 'pnputil scan' | Out-Null
Start-Sleep -Seconds 3

Invoke-GpuRecoverCommand -FilePath 'DisplaySwitch.exe' -ArgumentList @('/extend') -Label 'display extend after GPU restart' | Out-Null
Start-Sleep -Seconds 2

Invoke-DisplayWake

Write-PCModeLog 'GPU display recovery complete'
