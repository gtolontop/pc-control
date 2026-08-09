$ErrorActionPreference = 'Stop'

. 'C:\PCMode\remote-common.ps1'

New-PCModeLog -Name 'install-remote-tasks' | Out-Null

$scriptPath = 'C:\PCMode\parsec-repair.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 0)

if (Test-IsAdmin) {
    $user = "$env:USERDOMAIN\$env:USERNAME"
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest

    $startupTrigger = New-ScheduledTaskTrigger -AtStartup
    Register-ScheduledTask -TaskName 'PCMode_Parsec_KeepAlive_Startup' -Action $action -Trigger $startupTrigger -Principal $principal -Settings $settings -Force | Out-Null
    Write-PCModeLog 'Registered admin startup task: PCMode_Parsec_KeepAlive_Startup'
    Unregister-ScheduledTask -TaskName 'PCMode_Night_Watchdog_Startup' -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName 'PCMode_Night_Watchdog_Logon' -Confirm:$false -ErrorAction SilentlyContinue
    Write-PCModeLog 'Night watchdog tasks removed; hard monitor toggling is disabled on this setup'

    $logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    Register-ScheduledTask -TaskName 'PCMode_Parsec_KeepAlive_Logon' -Action $action -Trigger $logonTrigger -Principal $principal -Settings $settings -Force | Out-Null
    Write-PCModeLog 'Registered admin logon task: PCMode_Parsec_KeepAlive_Logon'
} else {
    $logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    Register-ScheduledTask -TaskName 'PCMode_Parsec_User_KeepAlive_Logon' -Action $action -Trigger $logonTrigger -Settings $settings -Force | Out-Null
    Write-PCModeLog 'Registered user logon task: PCMode_Parsec_User_KeepAlive_Logon'
    Write-PCModeLog 'Run this script as administrator later to add the machine startup task'
}

Write-PCModeLog 'Task installation complete'
