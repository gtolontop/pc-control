$ErrorActionPreference = 'Continue'

. 'C:\PCMode\remote-common.ps1'

New-PCModeLog -Name 'reset-display-registry' | Out-Null
Write-PCModeLog 'Starting display registry reset'

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $script:PCModeStateDir "display-registry-backup-$timestamp"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

function Invoke-ResetCommand {
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

$regRoots = @(
    'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration',
    'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Connectivity',
    'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\ScaleFactors'
)

foreach ($root in $regRoots) {
    $fileName = ($root -replace '[\\/:*?"<>|]', '_') + '.reg'
    $backupPath = Join-Path $backupDir $fileName
    Invoke-ResetCommand -FilePath 'reg.exe' -ArgumentList @('export', $root, $backupPath, '/y') -Label "backup $root" | Out-Null
}

foreach ($path in @(
    'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration',
    'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Connectivity',
    'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\ScaleFactors'
)) {
    if (Test-Path -LiteralPath $path) {
        Get-ChildItem -LiteralPath $path -ErrorAction SilentlyContinue | ForEach-Object {
            Write-PCModeLog "Removing display cache key: $($_.Name)"
            Remove-Item -LiteralPath $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-PCModeLog "Display registry backups saved to $backupDir"

$nvidia = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -match 'NVIDIA' } |
    Select-Object -First 1

if ($nvidia) {
    Write-PCModeLog ("Restarting NVIDIA adapter after registry reset: {0}" -f $nvidia.InstanceId)
    Invoke-ResetCommand -FilePath 'pnputil.exe' -ArgumentList @('/restart-device', $nvidia.InstanceId) -Label 'NVIDIA adapter restart' | Out-Null
    Start-Sleep -Seconds 8
}

Invoke-ResetCommand -FilePath 'pnputil.exe' -ArgumentList @('/scan-devices') -Label 'pnputil scan' | Out-Null
Start-Sleep -Seconds 3
Invoke-ResetCommand -FilePath 'DisplaySwitch.exe' -ArgumentList @('/extend') -Label 'display extend' | Out-Null
Start-Sleep -Seconds 2
Invoke-DisplayWake

Write-PCModeLog 'Display registry reset complete'
