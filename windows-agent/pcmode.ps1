param(
    [ValidateSet('Perf', 'Normal', 'Chill', 'Sleep', 'SleepServer', 'SleepHeavy', 'RemoteNight', 'RemoteNightGpu', 'Status', 'KeyboardReset')]
    [string]$Mode = 'Normal'
)

$ErrorActionPreference = 'Continue'

$BaseDir = 'C:\PCMode'
$LogDir = Join-Path $BaseDir 'logs'
if (-not (Test-Path -Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$script:LogPath = Join-Path $LogDir ("last-{0}.log" -f $Mode.ToLowerInvariant())
"=== PCMode $Mode $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File $script:LogPath

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
    $line | Out-File $script:LogPath -Append
}

function Invoke-LoggedCommand {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$Label = ''
    )

    $display = if ($Label) { $Label } else { $FilePath }
    Write-Log ("RUN {0}: {1} {2}" -f $display, $FilePath, ($ArgumentList -join ' '))
    try {
        & $FilePath @ArgumentList *>> $script:LogPath
        $code = $LASTEXITCODE
        if ($null -eq $code) { $code = 0 }
        Write-Log ("EXIT {0}: {1}" -f $display, $code)
        return [int]$code
    } catch {
        Write-Log ("ERROR {0}: {1}" -f $display, $_)
        return 999
    }
}

function Get-NvidiaSmiPath {
    $fixedPath = 'C:\Windows\System32\nvidia-smi.exe'
    if (Test-Path -Path $fixedPath) { return $fixedPath }
    $cmd = Get-Command 'nvidia-smi.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Set-PowerPlan {
    param([string]$Guid)
    Invoke-LoggedCommand -FilePath 'powercfg.exe' -ArgumentList @('/setactive', $Guid) -Label 'power plan' | Out-Null
}

function Set-PowerValue {
    param(
        [string]$SubGroup,
        [string]$Setting,
        [int]$AcValue,
        [int]$DcValue
    )

    Invoke-LoggedCommand -FilePath 'powercfg.exe' -ArgumentList @('/setacvalueindex', 'SCHEME_CURRENT', $SubGroup, $Setting, [string]$AcValue) -Label $Setting | Out-Null
    Invoke-LoggedCommand -FilePath 'powercfg.exe' -ArgumentList @('/setdcvalueindex', 'SCHEME_CURRENT', $SubGroup, $Setting, [string]$DcValue) -Label $Setting | Out-Null
}

function Apply-CpuProfile {
    param([hashtable]$Profile)

    $boost = 'be337238-0d82-4146-a960-4f3749d470c7'
    $epp = '36687f9e-e3a5-4dbf-b1dc-15eb381c6863'
    $coreParkingMin = '0cc5b647-c1df-4637-891a-dec35c318583'
    $diskTimeout = '6738e2c4-e8a5-4a42-b16a-e040e769756e'

    Set-PowerValue -SubGroup 'SUB_PROCESSOR' -Setting 'PROCTHROTTLEMAX' -AcValue $Profile.CpuMax -DcValue $Profile.CpuMax
    Set-PowerValue -SubGroup 'SUB_PROCESSOR' -Setting 'PROCTHROTTLEMIN' -AcValue $Profile.CpuMin -DcValue $Profile.CpuMin
    Set-PowerValue -SubGroup 'SUB_PROCESSOR' -Setting $boost -AcValue $Profile.BoostMode -DcValue $Profile.BoostMode
    Set-PowerValue -SubGroup 'SUB_PROCESSOR' -Setting $epp -AcValue $Profile.Epp -DcValue $Profile.Epp
    Set-PowerValue -SubGroup 'SUB_PROCESSOR' -Setting $coreParkingMin -AcValue $Profile.CoreParkingMin -DcValue $Profile.CoreParkingMin
    Set-PowerValue -SubGroup 'SUB_DISK' -Setting $diskTimeout -AcValue $Profile.DiskTimeoutSeconds -DcValue $Profile.DiskTimeoutSeconds
    Invoke-LoggedCommand -FilePath 'powercfg.exe' -ArgumentList @('/setactive', 'SCHEME_CURRENT') -Label 'apply power values' | Out-Null
}

function Apply-GpuProfile {
    param([hashtable]$Profile)

    $nvsmi = Get-NvidiaSmiPath
    if (-not $nvsmi) {
        Write-Log 'nvidia-smi not found, GPU settings skipped'
        return
    }

    if ($Profile.ContainsKey('GpuPowerLimit')) {
        Invoke-LoggedCommand -FilePath $nvsmi -ArgumentList @('-pl', [string]$Profile.GpuPowerLimit) -Label 'gpu power limit' | Out-Null
    }

    if ($Profile.GpuMode -eq 'Low') {
        Invoke-LoggedCommand -FilePath $nvsmi -ArgumentList @('-rgc') -Label 'gpu reset clocks before low lock' | Out-Null
        $exit = Invoke-LoggedCommand -FilePath $nvsmi -ArgumentList @('-lgc', ("{0},{1}" -f $Profile.GpuMinClock, $Profile.GpuMaxClock)) -Label 'gpu low clocks'
        if ($exit -ne 0) {
            Write-Log 'Low GPU clock lock was refused, falling back to 210,1200'
            Invoke-LoggedCommand -FilePath $nvsmi -ArgumentList @('-lgc', '210,1200') -Label 'gpu low fallback clocks' | Out-Null
        }
    } else {
        Invoke-LoggedCommand -FilePath $nvsmi -ArgumentList @('-rgc') -Label 'gpu reset clocks' | Out-Null
    }
}

function Set-FanControlProfile {
    param([string]$ProfileName)

    if (-not $ProfileName) { return }

    $fanControl = 'C:\Program Files (x86)\FanControl\FanControl.exe'
    $configPath = "C:\Program Files (x86)\FanControl\Configurations\$ProfileName.json"
    if ($ProfileName -eq 'SilentGpu' -and -not (Test-Path -Path $configPath)) {
        $silentPath = 'C:\Program Files (x86)\FanControl\Configurations\Silent.json'
        if (Test-Path -Path $silentPath) {
            $fanConfig = Get-Content -Path $silentPath -Raw | ConvertFrom-Json
            foreach ($control in $fanConfig.FanControl.Controls) {
                if ($control.Identifier -like 'NVApiWrapper/*/control/*') {
                    $control.Enable = $true
                    $control.ManualControl = $true
                    $control.ManualControlValue = 30
                    $control.ForceApply = $true
                }
            }
            $fanConfig | ConvertTo-Json -Depth 100 | Set-Content -Path $configPath -Encoding UTF8
            Write-Log 'Created SilentGpu FanControl profile with GPU fans fixed at 30%'
        }
    }
    if ((Test-Path -Path $fanControl) -and (Test-Path -Path $configPath)) {
        $existing = @(Get-Process -Name 'FanControl' -ErrorAction SilentlyContinue)
        if ($existing.Count -gt 0) {
            Write-Log ("Stopping existing FanControl instances: {0}" -f ($existing.Id -join ', '))
            $existing | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
        }

        Start-Process -FilePath $fanControl -ArgumentList @('--config', "$ProfileName.json") -WorkingDirectory (Split-Path -Path $fanControl -Parent) -WindowStyle Hidden
        Start-Sleep -Seconds 4
        $count = @(Get-Process -Name 'FanControl' -ErrorAction SilentlyContinue).Count
        Write-Log ("FanControl profile requested: {0}.json, running instances={1}" -f $ProfileName, $count)
    } else {
        Write-Log ("FanControl profile skipped, missing file: {0}" -f $configPath)
    }
}

function Set-QuietServices {
    param([bool]$Quiet)

    if ($Quiet) {
        Stop-Service -Name 'AsusFanControlService' -Force -ErrorAction SilentlyContinue
        Stop-Service -Name 'LightingService' -Force -ErrorAction SilentlyContinue
        Stop-Service -Name 'asus_framework' -Force -ErrorAction SilentlyContinue
        Write-Log 'Quiet services stopped'
    } else {
        Write-Log 'ASUS RGB/framework services intentionally left disabled'
    }
}

function Set-Notifications {
    param([bool]$Enabled)

    $value = if ($Enabled) { 1 } else { 0 }
    New-Item -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings' -Force | Out-Null
    New-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings' -Name 'NOC_GLOBAL_SETTING_TOASTS_ENABLED' -Value $value -PropertyType DWord -Force | Out-Null
    Write-Log ("Notifications enabled: {0}" -f $Enabled)
}

function Stop-QuietApps {
    param([string[]]$ProcessNames)

    foreach ($name in $ProcessNames) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    if ($ProcessNames.Count -gt 0) {
        Write-Log ("Quiet apps stopped: {0}" -f ($ProcessNames -join ', '))
    }
}

function Stop-AudioAntiIdleKeeper {
    $keeperScript = 'C:\PCMode\audio-anti-idle-keeper.ps1'
    $pidPath = 'C:\PCMode\state\audio-anti-idle-keeper.pid'

    if (Test-Path -LiteralPath $pidPath) {
        $keeperPid = [int](Get-Content -LiteralPath $pidPath -Raw -ErrorAction SilentlyContinue)
        if ($keeperPid -gt 0) {
            Stop-Process -Id $keeperPid -Force -ErrorAction SilentlyContinue
            Write-Log ("Audio anti-idle keeper stopped from pid file: {0}" -f $keeperPid)
        }
        Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    }

    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match [regex]::Escape($keeperScript) } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            Write-Log ("Audio anti-idle keeper stopped by command line: {0}" -f $_.ProcessId)
        }
}

function Invoke-RgbOff {
    $rgbScript = 'C:\PCMode\rgb-off.ps1'
    if (Test-Path -LiteralPath $rgbScript) {
        Invoke-LoggedCommand -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $rgbScript) -Label 'rgb off' | Out-Null
    } else {
        Write-Log 'RGB off skipped, script missing'
    }
}

function Turn-OffDisplays {
    try {
        if (-not ('PCMode.DisplayTools' -as [type])) {
            Add-Type -Name 'DisplayTools' -Namespace 'PCMode' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern int SendMessage(int hWnd, int hMsg, int wParam, int lParam);
'@
        }
        Start-Sleep -Milliseconds 800
        [PCMode.DisplayTools]::SendMessage(-1, 0x0112, 0xF170, 2) | Out-Null
        Write-Log 'Displays turned off'
    } catch {
        Write-Log ("Display off failed: {0}" -f $_)
    }
}

function Write-Status {
    $os = Get-CimInstance Win32_OperatingSystem
    $totalGb = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeGb = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedGb = [math]::Round($totalGb - $freeGb, 2)
    $commit = (Get-Counter '\Memory\Committed Bytes').CounterSamples.CookedValue
    $limit = (Get-Counter '\Memory\Commit Limit').CounterSamples.CookedValue
    $cpu = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 2).CounterSamples[-1].CookedValue
    $plan = (powercfg /getactivescheme) -join ' '

    $lines = @()
    $lines += '=== PCMode Status ==='
    $lines += ("Power plan: {0}" -f $plan)
    $lines += ("RAM: {0} GB used / {1} GB total ({2} GB free)" -f $usedGb, $totalGb, $freeGb)
    $lines += ("Commit: {0} GB / {1} GB" -f ([math]::Round($commit / 1GB, 2)), ([math]::Round($limit / 1GB, 2)))
    $lines += ("CPU: {0}%" -f ([math]::Round($cpu, 1)))

    $nvsmi = Get-NvidiaSmiPath
    if ($nvsmi) {
        $gpu = & $nvsmi --query-gpu=name,pstate,temperature.gpu,utilization.gpu,power.draw,power.limit,clocks.current.graphics,clocks.current.memory,memory.used,memory.total --format=csv,noheader,nounits
        $lines += ("GPU: {0}" -f ($gpu -join ' | '))
    }

    $lines += ''
    $lines += 'Top RAM groups:'
    $top = Get-Process |
        Group-Object ProcessName |
        ForEach-Object {
            $group = $_.Group
            [pscustomobject]@{
                Name = $_.Name
                Count = $_.Count
                PrivateGB = [math]::Round(($group | Measure-Object PrivateMemorySize64 -Sum).Sum / 1GB, 2)
                RAMGB = [math]::Round(($group | Measure-Object WorkingSet64 -Sum).Sum / 1GB, 2)
            }
        } |
        Sort-Object RAMGB -Descending |
        Select-Object -First 10

    foreach ($row in $top) {
        $lines += ("  {0} x{1}: RAM {2} GB, private {3} GB" -f $row.Name, $row.Count, $row.RAMGB, $row.PrivateGB)
    }

    foreach ($line in $lines) {
        Write-Output $line
        Write-Log $line
    }
}

function Reset-CorsairKeyboard {
    Write-Log 'Resetting Corsair K95 keyboard devices'

    $devices = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match 'VID_1B1C&PID_1B2D' -and $_.InstanceId -match '^USB\\' } |
        Sort-Object { if ($_.InstanceId -match '^USB\\VID_1B1C&PID_1B2D\\') { 0 } else { 1 } }

    foreach ($device in $devices) {
        Write-Log ("Device: {0} [{1}]" -f $device.FriendlyName, $device.InstanceId)
        try {
            if (Get-Command 'pnputil.exe' -ErrorAction SilentlyContinue) {
                Invoke-LoggedCommand -FilePath 'pnputil.exe' -ArgumentList @('/restart-device', $device.InstanceId) -Label 'keyboard restart' | Out-Null
            } else {
                Disable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false -ErrorAction Stop
                Start-Sleep -Seconds 2
                Enable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false -ErrorAction Stop
            }
        } catch {
            Write-Log ("Keyboard reset failed for {0}: {1}" -f $device.InstanceId, $_)
        }
    }

    Start-Service -Name 'CorsairService' -ErrorAction SilentlyContinue
    Start-Service -Name 'CorsairDeviceControlService' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Write-Log 'Keyboard reset finished'
}

$PowerPlans = @{
    Perf = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    Normal = '381b4222-f694-41f0-9685-ff5bb260df2e'
    Sleep = 'a1841308-3541-4fab-bc81-f71556f20b4a'
}

$Profiles = @{
    Perf = @{
        PowerPlan = $PowerPlans.Perf
        CpuMax = 100
        CpuMin = 5
        BoostMode = 4
        Epp = 20
        CoreParkingMin = 25
        DiskTimeoutSeconds = 0
        GpuMode = 'Normal'
        GpuPowerLimit = 320
        FanProfile = 'Default'
        QuietServices = $false
        Notifications = $true
        StopApps = @()
        ScreenOff = $false
    }
    Normal = @{
        PowerPlan = $PowerPlans.Normal
        CpuMax = 100
        CpuMin = 5
        BoostMode = 4
        Epp = 40
        CoreParkingMin = 10
        DiskTimeoutSeconds = 0
        GpuMode = 'Normal'
        GpuPowerLimit = 320
        FanProfile = 'Default'
        QuietServices = $false
        Notifications = $true
        StopApps = @()
        ScreenOff = $false
    }
    Chill = @{
        PowerPlan = $PowerPlans.Normal
        CpuMax = 80
        CpuMin = 5
        BoostMode = 2
        Epp = 70
        CoreParkingMin = 50
        DiskTimeoutSeconds = 600
        GpuMode = 'Low'
        GpuPowerLimit = 170
        GpuMinClock = 210
        GpuMaxClock = 1200
        FanProfile = 'Silent'
        QuietServices = $false
        Notifications = $true
        StopApps = @()
        ScreenOff = $false
    }
    Sleep = @{
        PowerPlan = $PowerPlans.Sleep
        CpuMax = 20
        CpuMin = 5
        BoostMode = 0
        Epp = 100
        CoreParkingMin = 25
        DiskTimeoutSeconds = 60
        GpuMode = 'Low'
        GpuPowerLimit = 150
        GpuMinClock = 210
        GpuMaxClock = 300
        FanProfile = 'Silent'
        QuietServices = $true
        Notifications = $false
        StopApps = @()
        ScreenOff = $true
    }
    SleepServer = @{
        PowerPlan = $PowerPlans.Sleep
        CpuMax = 55
        CpuMin = 5
        BoostMode = 0
        Epp = 85
        CoreParkingMin = 50
        DiskTimeoutSeconds = 60
        GpuMode = 'Low'
        GpuPowerLimit = 150
        GpuMinClock = 210
        GpuMaxClock = 300
        FanProfile = 'Silent'
        QuietServices = $true
        Notifications = $false
        StopApps = @()
        ScreenOff = $true
    }
    SleepHeavy = @{
        PowerPlan = $PowerPlans.Normal
        CpuMax = 80
        CpuMin = 5
        BoostMode = 3
        Epp = 65
        CoreParkingMin = 75
        DiskTimeoutSeconds = 300
        GpuMode = 'Low'
        GpuPowerLimit = 150
        GpuMinClock = 210
        GpuMaxClock = 300
        FanProfile = 'Silent'
        QuietServices = $true
        Notifications = $false
        StopApps = @()
        ScreenOff = $true
    }
    RemoteNight = @{
        PowerPlan = $PowerPlans.Sleep
        CpuMax = 20
        CpuMin = 5
        BoostMode = 0
        Epp = 100
        CoreParkingMin = 25
        DiskTimeoutSeconds = 60
        GpuMode = 'Low'
        GpuPowerLimit = 150
        GpuMinClock = 210
        GpuMaxClock = 300
        FanProfile = 'Silent'
        QuietServices = $true
        Notifications = $false
        StopApps = @()
        ScreenOff = $true
    }
    RemoteNightGpu = @{
        PowerPlan = $PowerPlans.Sleep
        CpuMax = 20
        CpuMin = 5
        BoostMode = 0
        Epp = 100
        CoreParkingMin = 25
        DiskTimeoutSeconds = 60
        GpuMode = 'Normal'
        GpuPowerLimit = 320
        FanProfile = 'SilentGpu'
        QuietServices = $true
        Notifications = $false
        StopApps = @()
        ScreenOff = $true
    }
}

if ($Mode -eq 'Status') {
    Write-Status
    "=== STATUS done ===" | Out-File $script:LogPath -Append
    exit 0
}

if ($Mode -eq 'KeyboardReset') {
    Reset-CorsairKeyboard
    Write-Status | Out-Null
    "=== KEYBOARD RESET done ===" | Out-File $script:LogPath -Append
    exit 0
}

$profile = $Profiles[$Mode]
Write-Log ("Applying profile: {0}" -f $Mode)
Set-PowerPlan -Guid $profile.PowerPlan
Apply-CpuProfile -Profile $profile
Apply-GpuProfile -Profile $profile
Set-FanControlProfile -ProfileName $profile.FanProfile
Set-QuietServices -Quiet $profile.QuietServices

# Screens off FIRST, before the slow RGB step. OpenRGB can stall for minutes
# (antivirus real-time scanning of its low-level hardware driver) and the
# PCMode_Perf scheduled task has a 5 min limit. Doing the display-off here means
# the screens go dark and the DDC night keeper starts even if RGB off later runs
# long or the task is terminated at its time limit.
if ($profile.ScreenOff) {
    Stop-AudioAntiIdleKeeper

    $nightModeScript = if ($Mode -in @('RemoteNight', 'RemoteNightGpu')) {
        Join-Path $BaseDir 'remote-night-on.ps1'
    } else {
        Join-Path $BaseDir 'night-mode-on.ps1'
    }
    if (Test-Path -Path $nightModeScript) {
        if ($Mode -in @('RemoteNight', 'RemoteNightGpu')) {
            Invoke-LoggedCommand -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $nightModeScript) -Label 'remote night on' | Out-Null
        } else {
            Invoke-LoggedCommand -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $nightModeScript, '-Profile', $Mode) -Label 'night mode on' | Out-Null
        }
    } else {
        Turn-OffDisplays
    }
}

Invoke-RgbOff
Set-Notifications -Enabled $profile.Notifications
Stop-QuietApps -ProcessNames $profile.StopApps

if (-not $profile.ScreenOff) {
    $remoteNightOffScript = Join-Path $BaseDir 'remote-night-off.ps1'
    if ($Mode -in @('Perf', 'Normal', 'Chill') -and (Test-Path -Path $remoteNightOffScript)) {
        Invoke-LoggedCommand -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $remoteNightOffScript) -Label 'remote night off' | Out-Null
    }

    $nightModeOffScript = Join-Path $BaseDir 'night-mode-off.ps1'
    if ($Mode -in @('Perf', 'Normal', 'Chill') -and (Test-Path -Path $nightModeOffScript)) {
        Invoke-LoggedCommand -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $nightModeOffScript) -Label 'night mode off' | Out-Null
    } else {
        Write-Log 'Display state unchanged'
    }
}

Write-Status | Out-Null
"=== PCMode $Mode done ===" | Out-File $script:LogPath -Append
