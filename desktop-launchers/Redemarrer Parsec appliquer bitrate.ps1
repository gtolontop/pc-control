param(
    [int]$Bitrate = 5
)

$ErrorActionPreference = "Stop"

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`"",
        "-Bitrate", "$Bitrate"
    )
    exit
}

Write-Host "Parsec va redemarrer dans 8 secondes. Tu pourras te reconnecter juste apres." -ForegroundColor Yellow
Start-Sleep -Seconds 8

$key = "HKLM:\SOFTWARE\Parsec"
if (Test-Path $key) {
    $props = Get-ItemProperty -Path $key
    foreach ($name in @("Configuration", "PCModeManagedConfiguration")) {
        $value = [string]$props.$name
        if ($value) {
            $parts = $value -split ":" | Where-Object { $_ -notmatch "^encoder_bitrate=" }
            Set-ItemProperty -Path $key -Name $name -Value ($parts -join ":")
        }
    }
}

$jsonPath = "C:\ProgramData\Parsec\config.json"
if (Test-Path $jsonPath) {
    $json = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
    if ($json.Count -ge 2) {
        $settings = $json[1]
        if (-not $settings.encoder_bitrate) {
            $settings | Add-Member -NotePropertyName "encoder_bitrate" -NotePropertyValue ([pscustomobject]@{ value = $Bitrate })
        } else {
            $settings.encoder_bitrate.value = $Bitrate
        }
        $json | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    }
}

$txtPath = "C:\ProgramData\Parsec\config.txt"
if (Test-Path $txtPath) {
    $lines = Get-Content -LiteralPath $txtPath
    $changed = $false
    $lines = $lines | ForEach-Object {
        if ($_ -match "^\s*encoder_bitrate\s*=") {
            $changed = $true
            "encoder_bitrate = $Bitrate"
        } else {
            $_
        }
    }
    if (-not $changed) {
        $lines += "encoder_bitrate = $Bitrate"
    }
    $lines | Set-Content -LiteralPath $txtPath -Encoding UTF8
}

$service = Get-Service -Name "Parsec" -ErrorAction Stop
if ($service.Status -eq "Running") {
    Stop-Service -Name "Parsec" -Force
}

Get-Process -Name "parsecd" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Service -Name "Parsec"

Start-Sleep -Seconds 4
$service = Get-Service -Name "Parsec" -ErrorAction Stop
if (-not (Get-Process -Name "parsecd" -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath "C:\Program Files\Parsec\parsecd.exe"
}
Write-Host "Parsec service: $($service.Status). Bitrate cible: $Bitrate Mbps." -ForegroundColor Green
Start-Sleep -Seconds 8
