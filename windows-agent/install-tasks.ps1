# Run ONCE as Administrator. Fait TOUT le setup d'un coup:
#  - Copie Silent.json/Default.json dans le dossier FanControl
#  - Enregistre 3 taches planifiees (Sleep, Perf, FanControl admin auto-start)
#  - Stoppe l'ancien FanControl (user mode) et le relance en admin

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "ERREUR: lance ce script en Administrateur (clic droit cmd > admin)." -ForegroundColor Red
    exit 1
}

$user = "$env:USERDOMAIN\$env:USERNAME"
$fcDir = "C:\Program Files (x86)\FanControl\Configurations"
$fcExe = "C:\Program Files (x86)\FanControl\FanControl.exe"

# 1) Copier les configs FanControl
Copy-Item "C:\PCMode\Silent.json"  "$fcDir\Silent.json"  -Force
Copy-Item "C:\PCMode\Default.json" "$fcDir\Default.json" -Force
Write-Host "Configs FanControl copiees: Silent.json, Default.json" -ForegroundColor Green

# 2) Enregistrer PCMode_Sleep + PCMode_Perf
function Register-PCMode($name, $script) {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Settings $settings -Force | Out-Null
    Write-Host "Tache enregistree: $name" -ForegroundColor Green
}
Register-PCMode 'PCMode_Sleep' 'C:\PCMode\sleep.ps1'
Register-PCMode 'PCMode_Perf'  'C:\PCMode\perf.ps1'

# 3) Tache FanControl_AutoStart: lance FanControl en admin a chaque ouverture de session
$fcAction = New-ScheduledTaskAction -Execute $fcExe -Argument '--minimized'
$fcTrigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$fcPrincipal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
$fcSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName 'FanControl_AutoStart' -Action $fcAction -Trigger $fcTrigger -Principal $fcPrincipal -Settings $fcSettings -Force | Out-Null
Write-Host "Tache enregistree: FanControl_AutoStart (lance FanControl admin a la session)" -ForegroundColor Green

# 4) Stop FanControl en cours (user mode), relance via la nouvelle tache (admin)
Get-Process FanControl -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-ScheduledTask -TaskName 'FanControl_AutoStart'
Start-Sleep -Seconds 3
Write-Host "FanControl relance en mode admin." -ForegroundColor Green

Write-Host ""
Write-Host "=== INSTALL TERMINEE ===" -ForegroundColor Cyan
Write-Host "Test SLEEP: schtasks /run /tn PCMode_Sleep" -ForegroundColor Cyan
Write-Host "Test PERF:  schtasks /run /tn PCMode_Perf" -ForegroundColor Cyan
