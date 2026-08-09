param(
    [switch]$KeepAsusAppsRunning
)

$ErrorActionPreference = 'Continue'

$BaseDir = 'C:\PCMode'
$LogDir = Join-Path $BaseDir 'logs'
if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$LogPath = Join-Path $LogDir 'last-rgb-off.log'
"=== RGB OFF $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -LiteralPath $LogPath -Encoding utf8

function Write-RgbLog {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
    $line | Out-File -LiteralPath $LogPath -Append -Encoding utf8
}

function Stop-AsusRgbControl {
    if ($KeepAsusAppsRunning) {
        Write-RgbLog 'ASUS app stop skipped by parameter'
        return
    }

    $serviceNames = @(
        'LightingService',
        'ArmouryCrateService',
        'asus_framework'
    )

    foreach ($name in $serviceNames) {
        try {
            Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
            Write-RgbLog "Requested ASUS RGB service stop: $name"
        } catch {
            Write-RgbLog "ASUS service stop failed for ${name}: $_"
        }
    }

    $processNames = @(
        'ArmouryCrate',
        'ArmouryCrate.UserSessionHelper',
        'AacKingstonDramHal_x64',
        'AacKingstonDramHal_x86',
        'Aac3572DramHal_x64',
        'Aac3572DramHal_x86',
        'Aac3572MbHal_x64',
        'Aac3572MbHal_x86',
        'extensionCardHal_x64',
        'extensionCardHal_x86',
        'LightingService'
    )

    foreach ($name in $processNames) {
        $matches = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
        foreach ($process in $matches) {
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                Write-RgbLog "Stopped ASUS RGB process: $($process.ProcessName) pid=$($process.Id)"
            } catch {
                Write-RgbLog "ASUS process stop failed for $($process.ProcessName) pid=$($process.Id): $_"
            }
        }
    }
}

function Get-OpenRgbPath {
    $candidates = @(
        'C:\PCMode\tools\OpenRGB\current\OpenRGB.exe',
        'C:\Program Files\OpenRGB\OpenRGB.exe',
        'C:\Program Files (x86)\OpenRGB\OpenRGB.exe',
        (Join-Path $env:LOCALAPPDATA 'Programs\OpenRGB\OpenRGB.exe')
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    $command = Get-Command 'OpenRGB.exe' -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    return $null
}

function Invoke-OpenRgbOff {
    param(
        [string]$OpenRgbPath,
        [string]$Device,
        [string[]]$ArgumentList
    )

    $label = $Device
    $args = @('--noautoconnect', '-d', $Device) + $ArgumentList
    Write-RgbLog "OpenRGB request: $label $($ArgumentList -join ' ')"
    try {
        & $OpenRgbPath @args *>> $LogPath
        $exit = $LASTEXITCODE
        if ($null -eq $exit) { $exit = 0 }
        Write-RgbLog "OpenRGB exit for ${label}: $exit"
    } catch {
        Write-RgbLog "OpenRGB failed for ${label}: $_"
    }
}

Stop-AsusRgbControl
Start-Sleep -Seconds 2

Get-Process -Name 'OpenRGB' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

$openRgb = Get-OpenRgbPath
if (-not $openRgb) {
    Write-RgbLog 'OpenRGB.exe not found; RGB off skipped'
    exit 2
}

Write-RgbLog "Using OpenRGB: $openRgb"

Write-RgbLog 'Targeting internal ASUS/Aura and Corsair controllers detected by OpenRGB'
$asusBoard = 'ASUS TUF GAMING B650-PLUS WIFI'
$asusAddressableZones = @(1, 2, 3)
$corsairNode = 'Corsair Lighting Node Core'
$corsairChannelZones = @(0, 1)

foreach ($zone in $asusAddressableZones) {
    Invoke-OpenRgbOff -OpenRgbPath $openRgb -Device $asusBoard -ArgumentList @('-z', [string]$zone, '-s', '24')
    Start-Sleep -Milliseconds 1200
}

foreach ($zone in $corsairChannelZones) {
    Invoke-OpenRgbOff -OpenRgbPath $openRgb -Device $corsairNode -ArgumentList @('-z', [string]$zone, '-s', '120')
    Start-Sleep -Milliseconds 1200
}

$requests = @(
    @{ Device = $asusBoard; Args = @('-m', 'off') },
    @{ Device = $asusBoard; Args = @('-m', 'direct', '-c', '000000') },
    @{ Device = $asusBoard; Args = @('-m', 'static', '-c', '000000', '-b', '0') },
    @{ Device = 'ASUS'; Args = @('-m', 'off') },
    @{ Device = 'AURA'; Args = @('-m', 'off') },
    @{ Device = $corsairNode; Args = @('-m', 'off') },
    @{ Device = $corsairNode; Args = @('-m', 'direct', '-c', '000000') },
    @{ Device = $corsairNode; Args = @('-m', 'static', '-c', '000000', '-b', '0') },
    @{ Device = 'Corsair Dominator Platinum'; Args = @('-m', 'off') },
    @{ Device = 'Corsair Dominator Platinum'; Args = @('-m', 'direct', '-c', '000000') },
    @{ Device = 'Corsair'; Args = @('-m', 'off') },
    @{ Device = 'Kingston'; Args = @('-m', 'off') },
    @{ Device = 'Patriot'; Args = @('-m', 'off') }
)

foreach ($request in $requests) {
    Invoke-OpenRgbOff -OpenRgbPath $openRgb -Device $request.Device -ArgumentList $request.Args
    Start-Sleep -Milliseconds 1200
}

Write-RgbLog 'RGB off sequence complete'
exit 0
