. 'C:\PCMode\remote-common.ps1'

New-PCModeLog -Name 'audit-parsec-host' | Out-Null

Write-PCModeLog '=== Parsec install ==='
$parsecExe = Get-Item -LiteralPath 'C:\Program Files\Parsec\parsecd.exe' -ErrorAction SilentlyContinue
$parsecServiceExe = Get-Item -LiteralPath 'C:\Program Files\Parsec\pservice.exe' -ErrorAction SilentlyContinue
if ($parsecExe -and $parsecServiceExe) {
    Write-PCModeLog 'Install type: Per Computer / service install'
    Write-PCModeLog "parsecd.exe: $($parsecExe.FullName)"
    Write-PCModeLog "pservice.exe: $($parsecServiceExe.FullName)"
} else {
    Write-PCModeLog 'Install type: not confirmed as Per Computer; check %APPDATA%\Parsec for per-user install'
}

$service = Get-Service -Name Parsec -ErrorAction SilentlyContinue
if ($service) {
    Write-PCModeLog "Service: $($service.Status), startup=$($service.StartType)"
} else {
    Write-PCModeLog 'Service: missing'
}

Write-PCModeLog '=== Parsec config ==='
if (Test-Path -LiteralPath $script:ParsecConfigTxtPath) {
    Write-PCModeLog "config.txt exists: $script:ParsecConfigTxtPath"
} else {
    Write-PCModeLog 'config.txt missing'
}

if (Test-Path -LiteralPath $script:ParsecConfigJsonPath) {
    try {
        $json = Get-Content -LiteralPath $script:ParsecConfigJsonPath -Raw | ConvertFrom-Json
        $settings = $json[1]
        foreach ($name in @('app_host', 'host_virtual_monitor_fallback', 'host_virtual_monitors', 'host_privacy_mode', 'server_admin_mute', 'host_audio_id', 'host_output', 'host_output_1', 'host_output_2')) {
            if ($settings.PSObject.Properties[$name]) {
                Write-PCModeLog "$name = $($settings.$name.value)"
            }
        }
    } catch {
        Write-PCModeLog "config.json unreadable: $_"
    }
} else {
    Write-PCModeLog 'config.json missing'
}

Write-PCModeLog '=== Virtual display / monitors ==='
Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -match 'Parsec|Virtual Display|Generic Monitor|NVIDIA|Realtek|XZ|LEN D' -or $_.InstanceId -match 'ROOT\\DISPLAY' } |
    Select-Object Class, Status, FriendlyName, InstanceId |
    ForEach-Object { Write-PCModeLog ("{0} | {1} | {2} | {3}" -f $_.Class, $_.Status, $_.FriendlyName, $_.InstanceId) }

Write-PCModeLog '=== Audio render endpoints ==='
Get-RenderAudioEndpoints |
    Sort-Object State, Name |
    ForEach-Object { Write-PCModeLog ("State={0} Active={1} Name={2} Id={3}" -f $_.State, $_.IsActive, $_.Name, $_.MMDeviceId) }

Write-PCModeLog '=== Power ==='
Write-PCModeLog ((powercfg /getactivescheme) -join ' ')
Write-PCModeLog ((powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE | Select-String -Pattern 'Current AC|Current DC' | ForEach-Object { $_.Line.Trim() }) -join ' | ')
Write-PCModeLog ((powercfg /query SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE | Select-String -Pattern 'Current AC|Current DC' | ForEach-Object { $_.Line.Trim() }) -join ' | ')

Write-PCModeLog 'Audit complete'
