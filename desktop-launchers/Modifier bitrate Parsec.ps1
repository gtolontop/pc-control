param(
    [int]$Bitrate = 0,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`""
    )
    exit
}

if ($Bitrate -eq 0) {
    $inputValue = Read-Host "Mbps Parsec souhaite (ex: 5, 10, 15, 20)"
    if ($inputValue -notmatch '^\d+$') {
        Write-Host "Valeur invalide. Mets un nombre entier, par exemple 5." -ForegroundColor Red
        pause
        exit 1
    }
    $Bitrate = [int]$inputValue
}

if ($Bitrate -lt 1 -or $Bitrate -gt 50) {
    Write-Host "Choisis entre 1 et 50 Mbps." -ForegroundColor Red
    pause
    exit 1
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = "C:\ProgramData\Parsec\parsec-registry-backup-$timestamp.reg"
reg export HKLM\SOFTWARE\Parsec $backup /y | Out-Null

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

Write-Host ""
Write-Host "OK: Parsec est regle a $Bitrate Mbps, et la policy registre encoder_bitrate a ete retiree." -ForegroundColor Green
Write-Host "Backup registre: $backup"
Write-Host "Ferme puis relance Parsec pour appliquer."
if (-not $Quiet) {
    pause
}
