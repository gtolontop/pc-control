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

Write-Host "Restart Parsec simple dans 5 secondes..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

$service = Get-Service -Name "Parsec" -ErrorAction Stop
if ($service.Status -eq "Running") {
    Stop-Service -Name "Parsec" -Force
}

Get-Process -Name "parsecd" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Service -Name "Parsec"
Start-Sleep -Seconds 5

$service = Get-Service -Name "Parsec" -ErrorAction Stop
Write-Host "Parsec service: $($service.Status)" -ForegroundColor Green
Start-Sleep -Seconds 5
