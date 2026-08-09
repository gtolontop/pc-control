param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Status', 'ShareParsec', 'RepairParsec', 'Normal', 'Night', 'LaunchCodex', 'RepairFans', 'Hibernate', 'Reboot')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'

$FanControlExe = 'C:\Program Files (x86)\FanControl\FanControl.exe'
$ParsecDaemonExe = 'C:\Program Files\Parsec\parsecd.exe'

function Write-Result {
    param([hashtable]$Data)

    # Le flux SSH de Windows n'est pas garanti UTF-8 : on échappe tout caractère
    # non ASCII en \uXXXX pour que le portail reçoive du JSON toujours décodable.
    $json = $Data | ConvertTo-Json -Compress -Depth 5
    $builder = [System.Text.StringBuilder]::new()
    foreach ($char in $json.ToCharArray()) {
        $code = [int]$char
        if ($code -lt 32 -or $code -gt 126) {
            [void]$builder.Append(('\u{0:x4}' -f $code))
        } else {
            [void]$builder.Append($char)
        }
    }
    $builder.ToString()
}

function Test-ProcessRunning {
    param([string]$Name)
    return [bool](@(Get-Process -Name $Name -ErrorAction SilentlyContinue).Count -gt 0)
}

function Get-ParsecPolicy {
    return (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Parsec' -ErrorAction SilentlyContinue).Configuration
}

function Test-ParsecHostEnabled {
    return [bool]((Get-ParsecPolicy) -match '(^|:)app_host=1(:|$)')
}

function Get-ParsecState {
    $service = Get-Service -Name Parsec -ErrorAction SilentlyContinue
    $running = [bool]($service -and $service.Status -eq 'Running')
    $host_enabled = Test-ParsecHostEnabled
    $daemon = Test-ProcessRunning -Name 'parsecd'
    return @{
        parsec = if ($service) { $service.Status.ToString() } else { 'Missing' }
        parsec_auto = [bool]($service -and $service.StartType -eq 'Automatic')
        parsec_host = $host_enabled
        parsec_daemon = $daemon
        parsec_ready = [bool]($running -and $host_enabled -and $daemon)
    }
}

function Get-PCStatus {
    $os = Get-CimInstance Win32_OperatingSystem
    $boot = $os.LastBootUpTime
    $scheme = (& powercfg.exe /getactivescheme 2>$null) -join ' '
    $identity = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    $cpu = Get-CimInstance Win32_Processor |
        Measure-Object -Property LoadPercentage -Average
    $systemDisk = Get-CimInstance Win32_LogicalDisk |
        Where-Object { $_.DeviceID -eq $env:SystemDrive } |
        Select-Object -First 1
    $memoryTotalGb = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $memoryFreeGb = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $memoryUsedPercent = if ($memoryTotalGb -gt 0) {
        [math]::Round((1 - ($memoryFreeGb / $memoryTotalGb)) * 100)
    } else {
        $null
    }

    $gpuTemperature = $null
    $gpuLoadPercent = $null
    $gpuMemoryUsedMb = $null
    $gpuMemoryTotalMb = $null
    $nvidiaSmi = 'C:\Windows\System32\nvidia-smi.exe'
    if (Test-Path -LiteralPath $nvidiaSmi) {
        try {
            $gpuLine = (& $nvidiaSmi `
                --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total `
                --format=csv,noheader,nounits 2>$null | Select-Object -First 1)
            if ($gpuLine) {
                $gpuValues = @($gpuLine -split ',' | ForEach-Object { $_.Trim() })
                if ($gpuValues.Count -ge 4) {
                    $gpuTemperature = [int]$gpuValues[0]
                    $gpuLoadPercent = [int]$gpuValues[1]
                    $gpuMemoryUsedMb = [int]$gpuValues[2]
                    $gpuMemoryTotalMb = [int]$gpuValues[3]
                }
            }
        } catch {
            # La télémétrie GPU reste optionnelle : Status doit toujours répondre.
        }
    }

    $result = @{
        ok = $true
        computer = $env:COMPUTERNAME
        mode = if (Test-Path -LiteralPath 'C:\PCMode\state\night-mode-active.json') { 'night' } else { 'normal' }
        power = if ($scheme -match '\(([^)]+)\)') { $Matches[1] } else { $scheme.Trim() }
        codex = Test-ProcessRunning -Name 'Codex'
        fan_control = Test-ProcessRunning -Name 'FanControl'
        booted_at = $boot.ToString('o')
        uptime_minutes = [math]::Floor(((Get-Date) - $boot).TotalMinutes)
        cpu_load_percent = if ($null -ne $cpu.Average) { [math]::Round($cpu.Average) } else { $null }
        memory_free_gb = $memoryFreeGb
        memory_total_gb = $memoryTotalGb
        memory_used_percent = $memoryUsedPercent
        disk_free_gb = if ($systemDisk) { [math]::Round($systemDisk.FreeSpace / 1GB, 1) } else { $null }
        disk_total_gb = if ($systemDisk) { [math]::Round($systemDisk.Size / 1GB, 1) } else { $null }
        disk_used_percent = if ($systemDisk -and $systemDisk.Size -gt 0) {
            [math]::Round((1 - ($systemDisk.FreeSpace / $systemDisk.Size)) * 100)
        } else {
            $null
        }
        gpu_temperature_c = $gpuTemperature
        gpu_load_percent = $gpuLoadPercent
        gpu_memory_used_mb = $gpuMemoryUsedMb
        gpu_memory_total_mb = $gpuMemoryTotalMb
        elevated = $identity.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    }

    foreach ($entry in (Get-ParsecState).GetEnumerator()) {
        $result[$entry.Key] = $entry.Value
    }

    Write-Result $result
}

function Enable-ParsecSharing {
    $service = Get-Service -Name Parsec -ErrorAction SilentlyContinue
    if (-not $service) {
        throw 'Le service Parsec est absent de cette machine.'
    }

    $steps = [System.Collections.Generic.List[string]]::new()

    if ($service.StartType -ne 'Automatic') {
        Set-Service -Name Parsec -StartupType Automatic -ErrorAction SilentlyContinue
        $steps.Add('démarrage auto rétabli')
    }

    if ($service.Status -ne 'Running') {
        Start-Service -Name Parsec -ErrorAction Stop
        Start-Sleep -Seconds 3
        $steps.Add('service démarré')
    }

    # L'hébergement doit être forcé côté machine, sinon le téléphone ne voit pas la tour.
    if (-not (Test-ParsecHostEnabled)) {
        & 'C:\PCMode\parsec-repair.ps1' -RestartParsec | Out-Null
        Start-Sleep -Seconds 3
        $steps.Add('hébergement réactivé')
    }

    # Parsec ferme parsecd.exe quand le dernier client se déconnecte : sans démon la tour
    # n'est plus joignable. Relancer le service est le seul moyen fiable de le respawn dans
    # la bonne session. On ne le fait que si le démon est absent, donc jamais pendant une session.
    if (-not (Test-ProcessRunning -Name 'parsecd')) {
        try {
            Restart-Service -Name Parsec -Force -ErrorAction Stop
            Start-Sleep -Seconds 6
            $steps.Add('service relancé')
        } catch {
            $steps.Add('relance du service impossible')
        }

        if (-not (Test-ProcessRunning -Name 'parsecd') -and (Test-Path -LiteralPath $ParsecDaemonExe)) {
            Start-Process -FilePath $ParsecDaemonExe -WindowStyle Hidden
            Start-Sleep -Seconds 3
            $steps.Add('démon lancé à la main')
        }
    }

    # Empêche la mise en veille : une tour endormie n'est plus joignable de l'extérieur.
    foreach ($setting in @('STANDBYIDLE', 'HIBERNATEIDLE', 'HYBRIDSLEEP')) {
        & powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_SLEEP $setting 0 2>$null | Out-Null
    }
    & powercfg.exe /setactive SCHEME_CURRENT 2>$null | Out-Null

    $state = Get-ParsecState
    $state.ok = $state.parsec_ready
    $detail = if ($steps.Count -gt 0) { ' (' + ($steps -join ', ') + ')' } else { '' }
    $state.message = if ($state.parsec_ready) {
        "PC partagé, Parsec hôte est prêt$detail."
    } elseif (-not $state.parsec_host) {
        'Parsec tourne mais l''hébergement reste désactivé.'
    } elseif (-not $state.parsec_daemon) {
        "Service Parsec en marche mais le démon hôte ne remonte pas$detail."
    } else {
        "Parsec n'est pas prêt : service $($state.parsec)."
    }
    Write-Result $state
}

function Restart-FanControl {
    if (Test-ProcessRunning -Name 'FanControl') {
        Write-Result @{ ok = $true; message = 'FanControl tourne déjà.'; fan_control = $true }
        return
    }

    $started = $false
    $task = Get-ScheduledTask -TaskName 'FanControl_AutoStart' -ErrorAction SilentlyContinue
    if ($task) {
        Start-ScheduledTask -TaskName 'FanControl_AutoStart' -ErrorAction SilentlyContinue
        $started = $true
    } elseif (Test-Path -LiteralPath $FanControlExe) {
        Start-Process -FilePath $FanControlExe -ArgumentList '--minimized'
        $started = $true
    }

    if (-not $started) {
        throw 'FanControl est introuvable (ni tâche planifiée, ni exécutable).'
    }

    Start-Sleep -Seconds 4
    $running = Test-ProcessRunning -Name 'FanControl'
    Write-Result @{
        ok = $running
        fan_control = $running
        message = if ($running) {
            'FanControl relancé, les courbes personnalisées sont actives.'
        } else {
            'FanControl ne démarre pas ; les courbes BIOS protègent quand même la machine.'
        }
    }
}

try {
    switch ($Action) {
        'Status' {
            Get-PCStatus
        }

        'ShareParsec' {
            Enable-ParsecSharing
        }

        'RepairParsec' {
            & 'C:\PCMode\parsec-repair.ps1' -RestartParsec | Out-Null
            $state = Get-ParsecState
            $state.ok = [bool]($state.parsec -eq 'Running')
            $state.message = if ($state.parsec_ready) {
                'Parsec réparé, relancé et prêt à héberger.'
            } elseif ($state.parsec -eq 'Running') {
                'Parsec relancé mais l''hébergement reste à vérifier.'
            } else {
                'Parsec ne tourne pas après la réparation.'
            }
            Write-Result $state
        }

        'Normal' {
            & 'C:\PCMode\remote-night-off.ps1' -Force
            & powercfg.exe /setactive 381b4222-f694-41f0-9685-ff5bb260df2e | Out-Null
            $nvidiaSmi = 'C:\Windows\System32\nvidia-smi.exe'
            if (Test-Path -LiteralPath $nvidiaSmi) {
                & $nvidiaSmi -rgc | Out-Null
                & $nvidiaSmi -pl 320 | Out-Null
            }
            Write-Result @{ ok = $true; message = 'Mode normal restauré.'; mode = 'normal' }
        }

        'Night' {
            & 'C:\PCMode\remote-night-on.ps1' -SkipParsecRestart
            Write-Result @{ ok = $true; message = 'Mode nuit activé sans couper Parsec.'; mode = 'night' }
        }

        'LaunchCodex' {
            Start-ScheduledTask -TaskName 'PCControl_LaunchCodex'
            Start-Sleep -Seconds 5
            $running = Test-ProcessRunning -Name 'Codex'
            Write-Result @{
                ok = $true
                codex = $running
                message = if ($running) { 'Codex est ouvert sur la tour.' } else { 'Lancement de Codex demandé.' }
            }
        }

        'RepairFans' {
            Restart-FanControl
        }

        'Hibernate' {
            & powercfg.exe /hibernate on | Out-Null
            & powercfg.exe /hibernate /type full | Out-Null
            Start-ScheduledTask -TaskName 'PCControl_Hibernate'
            Write-Result @{
                ok = $true
                message = 'Extinction fiable demandée. Le Wake-on-LAN reste armé.'
            }
        }

        'Reboot' {
            & shutdown.exe /r /t 10 /c 'Redémarrage demandé depuis PC Control'
            Write-Result @{ ok = $true; message = 'Redémarrage dans 10 secondes.' }
        }
    }
    # Les outils de télémétrie optionnels (notamment nvidia-smi) peuvent laisser
    # un LASTEXITCODE non nul malgré un statut JSON valide. Le résultat du pont
    # est celui de ce script, pas celui du dernier exécutable interrogé.
    exit 0
} catch {
    Write-Result @{ ok = $false; error = $_.Exception.Message; action = $Action }
    exit 1
}
