$ErrorActionPreference = 'Continue'

$script:PCModeBaseDir = 'C:\PCMode'
$script:PCModeLogDir = Join-Path $script:PCModeBaseDir 'logs'
$script:PCModeStateDir = Join-Path $script:PCModeBaseDir 'state'
$script:RemoteConfigPath = Join-Path $script:PCModeBaseDir 'remote-mode.config.json'
$script:ParsecDataDir = 'C:\ProgramData\Parsec'
$script:ParsecConfigJsonPath = Join-Path $script:ParsecDataDir 'config.json'
$script:ParsecConfigTxtPath = Join-Path $script:ParsecDataDir 'config.txt'
$script:ParsecRegistryPath = 'HKLM:\SOFTWARE\Parsec'

New-Item -ItemType Directory -Path $script:PCModeLogDir -Force | Out-Null
New-Item -ItemType Directory -Path $script:PCModeStateDir -Force | Out-Null

function New-PCModeLog {
    param([string]$Name)

    $safeName = ($Name -replace '[^A-Za-z0-9_.-]', '-').ToLowerInvariant()
    $script:CurrentLogPath = Join-Path $script:PCModeLogDir ("last-{0}.log" -f $safeName)
    "=== $Name $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -LiteralPath $script:CurrentLogPath -Encoding UTF8
    return $script:CurrentLogPath
}

function Write-PCModeLog {
    param([string]$Message)

    if (-not $script:CurrentLogPath) {
        New-PCModeLog -Name 'remote-common' | Out-Null
    }
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
    $line | Out-File -LiteralPath $script:CurrentLogPath -Append -Encoding UTF8
    Write-Output $line
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Get-RemoteModeConfig {
    $defaults = [ordered]@{
        EnableParsecPrivacyMode = $true
        EnableFallbackVirtualDisplay = $true
        VirtualDisplayCount = 1
        AggressiveDisablePhysicalMonitors = $false
        DisablePhysicalMonitorsDuringParsec = $false
        UseDdcMonitorPowerOff = $true
        UseWindowsDisplayPowerOffFallback = $false
        WatchdogIntervalSeconds = 3
        ParsecStreamFpsTimeoutSeconds = 30
        LockWorkstationOnNightMode = $false
        PreferredVirtualAudioPattern = 'CABLE|VB-Audio|Voicemeeter|Steam Streaming Speakers'
        PreferredLocalAudioId = ''
        PreferredLocalAudioPattern = 'Realtek|Haut-parleurs'
        RemovePinnedPhysicalParsecOutputs = $true
        KeepHostMutedWithoutVirtualAudio = $true
        KeepHostMutedWithVirtualAudio = $false
        ResetPerAppAudioRoutingInNightMode = $false
    }

    if (Test-Path -LiteralPath $script:RemoteConfigPath) {
        try {
            $loaded = Get-Content -LiteralPath $script:RemoteConfigPath -Raw | ConvertFrom-Json
            foreach ($prop in $loaded.PSObject.Properties) {
                $defaults[$prop.Name] = $prop.Value
            }
        } catch {
            Write-PCModeLog "Remote config unreadable, defaults used: $_"
        }
    }

    return [pscustomobject]$defaults
}

function Get-NightModeFlagPath {
    return (Join-Path $script:PCModeStateDir 'night-mode-active.flag')
}

function Set-NightModeActiveFlag {
    param([string]$Profile)

    $flag = Get-NightModeFlagPath
    [pscustomobject]@{
        ActiveAt = (Get-Date).ToString('o')
        Profile = $Profile
    } | ConvertTo-Json -Depth 3 | Out-File -LiteralPath $flag -Encoding UTF8
    Write-PCModeLog "Night mode active flag written: $flag"
}

function Clear-NightModeActiveFlag {
    $flag = Get-NightModeFlagPath
    Remove-Item -LiteralPath $flag -Force -ErrorAction SilentlyContinue
    Write-PCModeLog "Night mode active flag cleared: $flag"
}

function Test-NightModeActive {
    return (Test-Path -LiteralPath (Get-NightModeFlagPath))
}

function Backup-File {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $leaf = Split-Path -Path $Path -Leaf
    $backup = Join-Path $script:PCModeStateDir ("{0}.backup-{1}" -f $leaf, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Copy-Item -LiteralPath $Path -Destination $backup -Force
    Write-PCModeLog "Backed up $Path to $backup"
    return $backup
}

function Get-RenderAudioEndpoints {
    $root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'
    if (-not (Test-Path -LiteralPath $root)) {
        return @()
    }

    Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty -LiteralPath (Join-Path $_.PSPath 'Properties') -ErrorAction SilentlyContinue
        $state = (Get-ItemProperty -LiteralPath $_.PSPath -Name DeviceState -ErrorAction SilentlyContinue).DeviceState
        $name = $props.'{a45c254e-df1c-4efd-8020-67d146a850e0},2'
        $mmDeviceId = "{0.0.0.00000000}.$($_.PSChildName)"
        [pscustomobject]@{
            Name = $name
            State = $state
            RegistryKey = $_.PSChildName
            MMDeviceId = $mmDeviceId
            IsActive = ($state -eq 1)
        }
    }
}

function Get-PreferredVirtualAudioEndpoint {
    param([pscustomobject]$Config)

    $pattern = [string]$Config.PreferredVirtualAudioPattern
    if ([string]::IsNullOrWhiteSpace($pattern)) {
        return $null
    }

    return Get-RenderAudioEndpoints |
        Where-Object { $_.IsActive -and $_.Name -match $pattern } |
        Select-Object -First 1
}

function Get-PreferredLocalAudioEndpoint {
    param([pscustomobject]$Config)

    $preferredId = [string]$Config.PreferredLocalAudioId
    if (-not [string]::IsNullOrWhiteSpace($preferredId)) {
        $endpoint = Get-RenderAudioEndpoints |
            Where-Object { $_.IsActive -and $_.MMDeviceId -ieq $preferredId } |
            Select-Object -First 1
        if ($endpoint) {
            return $endpoint
        }
    }

    $pattern = [string]$Config.PreferredLocalAudioPattern
    if ([string]::IsNullOrWhiteSpace($pattern)) {
        return $null
    }

    return Get-RenderAudioEndpoints |
        Where-Object { $_.IsActive -and $_.Name -match $pattern } |
        Select-Object -First 1
}

function Ensure-AudioPolicyTools {
    if ('PCMode.AudioPolicyTools' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace PCMode {
    public enum AudioRole {
        Console = 0,
        Multimedia = 1,
        Communications = 2
    }

    [ComImport, Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")]
    public class PolicyConfigClient {}

    [ComImport, Guid("f8679f50-850a-41cf-9c72-430f290290c8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPolicyConfig {
        int GetMixFormat([MarshalAs(UnmanagedType.LPWStr)] string deviceName, out IntPtr mixFormat);
        int GetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string deviceName, bool defaultFormat, out IntPtr deviceFormat);
        int ResetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string deviceName);
        int SetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string deviceName, IntPtr endpointFormat, IntPtr mixFormat);
        int GetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string deviceName, bool defaultPeriod, out long defaultPeriodValue, out long minimumPeriodValue);
        int SetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string deviceName, ref long periodValue);
        int GetShareMode([MarshalAs(UnmanagedType.LPWStr)] string deviceName, out IntPtr mode);
        int SetShareMode([MarshalAs(UnmanagedType.LPWStr)] string deviceName, IntPtr mode);
        int GetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string deviceName, IntPtr key, out IntPtr propvariant);
        int SetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string deviceName, IntPtr key, IntPtr propvariant);
        int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string deviceName, AudioRole role);
        int SetEndpointVisibility([MarshalAs(UnmanagedType.LPWStr)] string deviceName, bool visible);
    }

    public static class AudioPolicyTools {
        public static void SetDefaultRenderEndpoint(string deviceId) {
            var policy = (IPolicyConfig)(new PolicyConfigClient());
            foreach (AudioRole role in Enum.GetValues(typeof(AudioRole))) {
                int hr = policy.SetDefaultEndpoint(deviceId, role);
                if (hr != 0) {
                    Marshal.ThrowExceptionForHR(hr);
                }
            }
        }
    }
}
'@
}

function Ensure-AudioEndpointTools {
    if ('PCMode.AudioEndpointTools' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace PCMode {
    public enum EndpointDataFlow {
        Render = 0,
        Capture = 1,
        All = 2
    }

    public enum EndpointRole {
        Console = 0,
        Multimedia = 1,
        Communications = 2
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    public class MMDeviceEnumerator {}

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDeviceEnumerator {
        int EnumAudioEndpoints(EndpointDataFlow dataFlow, int stateMask, out IntPtr devices);
        int GetDefaultAudioEndpoint(EndpointDataFlow dataFlow, EndpointRole role, out IMMDevice endpoint);
        int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice endpoint);
        int RegisterEndpointNotificationCallback(IntPtr client);
        int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDevice {
        int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, out IntPtr interfacePointer);
        int OpenPropertyStore(int accessMode, out IntPtr properties);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        int GetState(out int state);
    }

    public static class AudioEndpointTools {
        public static string GetDefaultRenderEndpointId() {
            var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumerator());
            IMMDevice endpoint = null;
            try {
                int hr = enumerator.GetDefaultAudioEndpoint(EndpointDataFlow.Render, EndpointRole.Multimedia, out endpoint);
                if (hr != 0) {
                    Marshal.ThrowExceptionForHR(hr);
                }

                string id;
                hr = endpoint.GetId(out id);
                if (hr != 0) {
                    Marshal.ThrowExceptionForHR(hr);
                }

                return id;
            } finally {
                if (endpoint != null) {
                    Marshal.ReleaseComObject(endpoint);
                }
                Marshal.ReleaseComObject(enumerator);
            }
        }
    }
}
'@
}

function Get-DefaultRenderAudioEndpoint {
    try {
        Ensure-AudioEndpointTools
        $defaultId = [PCMode.AudioEndpointTools]::GetDefaultRenderEndpointId()
        if ([string]::IsNullOrWhiteSpace($defaultId)) {
            Write-PCModeLog 'Windows default render audio lookup returned an empty endpoint id'
            return $null
        }

        $endpoint = Get-RenderAudioEndpoints |
            Where-Object { $_.MMDeviceId -ieq $defaultId } |
            Select-Object -First 1

        if ($endpoint) {
            return $endpoint
        }

        return [pscustomobject]@{
            Name = $defaultId
            State = $null
            RegistryKey = $null
            MMDeviceId = $defaultId
            IsActive = $null
        }
    } catch {
        Write-PCModeLog "Could not read Windows default render audio endpoint: $_"
        return $null
    }
}

function Set-DefaultRenderAudioEndpoint {
    param([pscustomobject]$Endpoint)

    if (-not $Endpoint -or [string]::IsNullOrWhiteSpace([string]$Endpoint.MMDeviceId)) {
        Write-PCModeLog 'Default audio endpoint update skipped because no endpoint was provided'
        return $false
    }

    try {
        Ensure-AudioPolicyTools
        [PCMode.AudioPolicyTools]::SetDefaultRenderEndpoint([string]$Endpoint.MMDeviceId)
        Write-PCModeLog "Windows default render audio set to: $($Endpoint.Name) [$($Endpoint.MMDeviceId)]"
        return $true
    } catch {
        Write-PCModeLog "Could not set Windows default render audio endpoint: $_"
        return $false
    }
}

function Restore-SavedDefaultAudioEndpoint {
    param([string]$StatePath = (Join-Path $script:PCModeStateDir 'night-mode-state.json'))

    if (-not (Test-Path -LiteralPath $StatePath)) {
        Write-PCModeLog "Saved audio restore skipped because state file is missing: $StatePath"
        return $false
    }

    try {
        $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
        $savedId = [string]$state.DefaultRenderAudioId
        $savedName = [string]$state.DefaultRenderAudioName

        if ([string]::IsNullOrWhiteSpace($savedId)) {
            Write-PCModeLog 'Saved audio restore skipped because the state file has no default audio endpoint'
            return $false
        }

        $endpoint = Get-RenderAudioEndpoints |
            Where-Object { $_.IsActive -and $_.MMDeviceId -ieq $savedId } |
            Select-Object -First 1

        if (-not $endpoint) {
            Write-PCModeLog "Saved audio endpoint is not active anymore; restore skipped: $savedName [$savedId]"
            return $false
        }

        Write-PCModeLog "Restoring saved Windows default render audio: $($endpoint.Name) [$($endpoint.MMDeviceId)]"
        return (Set-DefaultRenderAudioEndpoint -Endpoint $endpoint)
    } catch {
        Write-PCModeLog "Could not restore saved Windows default render audio endpoint: $_"
        return $false
    }
}

function Reset-AppAudioRouting {
    param([string]$Reason = 'PCMode audio self-heal')

    $storeReg = 'HKCU\Software\Microsoft\Internet Explorer\LowRegistry\Audio\PolicyConfig\PropertyStore'
    $storePs = 'HKCU:\Software\Microsoft\Internet Explorer\LowRegistry\Audio\PolicyConfig\PropertyStore'

    try {
        if (Test-Path -LiteralPath $storePs) {
            $backupPath = Join-Path $script:PCModeStateDir ("audio-policy-store.backup-{0}.reg" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
            & reg.exe export $storeReg $backupPath /y *>> $script:CurrentLogPath
            Write-PCModeLog "Per-app audio routing backed up to $backupPath"
            Remove-Item -LiteralPath $storePs -Recurse -Force -ErrorAction Stop
        }

        New-Item -Path $storePs -Force | Out-Null
        Write-PCModeLog "Per-app audio routing reset: $Reason"
        return $true
    } catch {
        Write-PCModeLog "Could not reset per-app audio routing: $_"
        return $false
    }
}

function Get-PhysicalMonitorDevices {
    Get-PnpDevice -Class Monitor -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object {
            $_.InstanceId -notmatch 'ROOT\\DISPLAY' -and
            $_.FriendlyName -notmatch 'Parsec|Virtual'
        }
}

function Save-NightModeState {
    param([string]$Profile)

    $statePath = Join-Path $script:PCModeStateDir 'night-mode-state.json'
    $powerScheme = (powercfg /getactivescheme) -join ' '
    $monitors = Get-PhysicalMonitorDevices | ForEach-Object {
        [pscustomobject]@{
            FriendlyName = $_.FriendlyName
            InstanceId = $_.InstanceId
            Status = $_.Status
        }
    }
    $defaultAudio = Get-DefaultRenderAudioEndpoint

    $state = [pscustomobject]@{
        SavedAt = (Get-Date).ToString('o')
        Profile = $Profile
        PowerScheme = $powerScheme
        PhysicalMonitors = @($monitors)
        RenderAudioEndpoints = @(Get-RenderAudioEndpoints)
        DefaultRenderAudioName = if ($defaultAudio) { $defaultAudio.Name } else { $null }
        DefaultRenderAudioId = if ($defaultAudio) { $defaultAudio.MMDeviceId } else { $null }
    }

    $state | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $statePath -Encoding UTF8
    Write-PCModeLog "Night mode state saved to $statePath"
    return $statePath
}

function Set-ComputerStayAwake {
    # Keep the machine reachable; only the display is allowed to turn off.
    $commands = @(
        @('/setacvalueindex', 'SCHEME_CURRENT', 'SUB_SLEEP', 'STANDBYIDLE', '0'),
        @('/setacvalueindex', 'SCHEME_CURRENT', 'SUB_SLEEP', 'HIBERNATEIDLE', '0'),
        @('/setacvalueindex', 'SCHEME_CURRENT', 'SUB_SLEEP', 'HYBRIDSLEEP', '0'),
        @('/setactive', 'SCHEME_CURRENT')
    )

    foreach ($args in $commands) {
        & powercfg.exe @args *>> $script:CurrentLogPath
        Write-PCModeLog "powercfg $($args -join ' ') exit=$LASTEXITCODE"
    }
}

function Invoke-DisplayOff {
    try {
        if (-not ('PCMode.DisplayTools' -as [type])) {
            Add-Type -Name 'DisplayTools' -Namespace 'PCMode' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern int SendMessage(int hWnd, int hMsg, int wParam, int lParam);
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError=true)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.IntPtr wParam, System.IntPtr lParam, uint fuFlags, uint uTimeout, out System.IntPtr lpdwResult);
'@
        }
        Start-Sleep -Milliseconds 800
        $result = [IntPtr]::Zero
        [PCMode.DisplayTools]::SendMessageTimeout([IntPtr]::new(-1), 0x0112, [IntPtr]0xF170, [IntPtr]2, 0x0002, 1000, [ref]$result) | Out-Null
        Write-PCModeLog 'Physical displays requested off through Windows display power message'
    } catch {
        Write-PCModeLog "Display-off request failed: $_"
    }
}

function Invoke-DisplayWake {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $pos = [System.Windows.Forms.Cursor]::Position
        [System.Windows.Forms.Cursor]::Position = [System.Drawing.Point]::new($pos.X + 1, $pos.Y)
        Start-Sleep -Milliseconds 100
        [System.Windows.Forms.Cursor]::Position = $pos
        Write-PCModeLog 'Display wake requested by a tiny cursor move'
    } catch {
        Write-PCModeLog "Display wake request failed: $_"
    }
}

function Disable-PhysicalMonitors {
    $disabled = @()
    foreach ($monitor in Get-PhysicalMonitorDevices) {
        try {
            Disable-PnpDevice -InstanceId $monitor.InstanceId -Confirm:$false -ErrorAction Stop
            Write-PCModeLog "Disabled physical monitor: $($monitor.FriendlyName) [$($monitor.InstanceId)]"
            $disabled += [pscustomobject]@{
                FriendlyName = $monitor.FriendlyName
                InstanceId = $monitor.InstanceId
            }
        } catch {
            Write-PCModeLog "Could not disable monitor $($monitor.InstanceId): $_"
        }
    }

    $path = Join-Path $script:PCModeStateDir 'disabled-monitors.json'
    $disabled | ConvertTo-Json -Depth 4 | Out-File -LiteralPath $path -Encoding UTF8
    return $disabled
}

function Enable-PhysicalMonitors {
    $statePath = Join-Path $script:PCModeStateDir 'disabled-monitors.json'
    $targets = @()

    if (Test-Path -LiteralPath $statePath) {
        try {
            $targets = @(Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json)
        } catch {
            Write-PCModeLog "Could not read disabled monitor state: $_"
        }
    }

    if ($targets.Count -eq 0) {
        $targets = @(Get-PnpDevice -Class Monitor -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -notmatch 'ROOT\\DISPLAY' -and $_.FriendlyName -notmatch 'Parsec|Virtual' })
    }

    foreach ($monitor in $targets) {
        try {
            Enable-PnpDevice -InstanceId $monitor.InstanceId -Confirm:$false -ErrorAction Stop
            Write-PCModeLog "Enabled physical monitor: $($monitor.FriendlyName) [$($monitor.InstanceId)]"
        } catch {
            Write-PCModeLog "Could not enable monitor $($monitor.InstanceId): $_"
        }
    }

    & DisplaySwitch.exe /extend *>> $script:CurrentLogPath
    Write-PCModeLog "DisplaySwitch /extend exit=$LASTEXITCODE"
}

function Test-ParsecActiveStream {
    param([int]$TimeoutSeconds = 30)

    $logPath = Join-Path $script:ParsecDataDir 'log.txt'
    if (-not (Test-Path -LiteralPath $logPath)) {
        return $false
    }

    try {
        $lines = Get-Content -LiteralPath $logPath -Tail 120 -ErrorAction Stop
        $now = Get-Date
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            $line = [string]$lines[$i]
            if ($line -notmatch 'FPS:') {
                continue
            }

            if ($line -match '^\[[A-Z]\s+(?<stamp>\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\]') {
                $stamp = [datetime]::MinValue
                if ([datetime]::TryParseExact($matches.stamp, 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeLocal, [ref]$stamp)) {
                    return (($now - $stamp).TotalSeconds -le $TimeoutSeconds)
                }
            }

            return ((Get-Item -LiteralPath $logPath).LastWriteTime -gt $now.AddSeconds(-1 * $TimeoutSeconds))
        }
    } catch {
        Write-PCModeLog "Could not inspect Parsec stream state: $_"
    }

    return $false
}

function Ensure-ParsecService {
    $service = Get-Service -Name Parsec -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-PCModeLog 'Parsec service not found'
        return $false
    }

    try {
        if ($service.StartType -ne 'Automatic') {
            Set-Service -Name Parsec -StartupType Automatic -ErrorAction Stop
            Write-PCModeLog 'Parsec service startup set to Automatic'
        }
    } catch {
        Write-PCModeLog "Could not set Parsec startup type, likely not admin: $_"
    }

    try {
        if ($service.Status -ne 'Running') {
            Start-Service -Name Parsec -ErrorAction Stop
            Write-PCModeLog 'Parsec service started'
        } else {
            Write-PCModeLog 'Parsec service already running'
        }
    } catch {
        Write-PCModeLog "Could not start Parsec service: $_"
        return $false
    }

    Start-Sleep -Milliseconds 500
    $daemon = @(Get-Process -Name 'parsecd' -ErrorAction SilentlyContinue)
    if ($daemon.Count -eq 0) {
        $daemonPath = 'C:\Program Files\Parsec\parsecd.exe'
        if (Test-Path -LiteralPath $daemonPath) {
            try {
                Start-Process -FilePath $daemonPath -WindowStyle Hidden
                Write-PCModeLog "Parsec daemon started from $daemonPath"
            } catch {
                Write-PCModeLog "Could not start Parsec daemon manually: $_"
            }
        } else {
            Write-PCModeLog 'Parsec daemon process not found and parsecd.exe path is missing'
        }
    } else {
        Write-PCModeLog "Parsec daemon process count: $($daemon.Count)"
    }

    return $true
}

function Set-JsonSetting {
    param(
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value
    )

    if ($Settings.PSObject.Properties[$Name]) {
        $Settings.$Name.value = $Value
    } else {
        $Settings | Add-Member -MemberType NoteProperty -Name $Name -Value ([pscustomobject]@{ value = $Value })
    }
}

function Remove-JsonSetting {
    param(
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][string]$Name
    )

    if ($Settings.PSObject.Properties[$Name]) {
        $Settings.PSObject.Properties.Remove($Name)
    }
}

function Set-ParsecConfigTextBlock {
    param([hashtable]$Settings)

    $begin = '# BEGIN PCMode managed remote host config'
    $end = '# END PCMode managed remote host config'
    $existing = ''
    if (Test-Path -LiteralPath $script:ParsecConfigTxtPath) {
        $existing = Get-Content -LiteralPath $script:ParsecConfigTxtPath -Raw
    }

    $beginPattern = [regex]::Escape($begin)
    $endPattern = [regex]::Escape($end)
    $clean = [regex]::Replace($existing, "(?ms)$beginPattern.*?$endPattern\s*", '')
    $lines = @($begin)
    foreach ($key in ($Settings.Keys | Sort-Object)) {
        $lines += ("{0} = {1}" -f $key, $Settings[$key])
    }
    $lines += $end

    ($clean.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + ($lines -join [Environment]::NewLine) + [Environment]::NewLine) |
        Out-File -LiteralPath $script:ParsecConfigTxtPath -Encoding UTF8
    Write-PCModeLog "Updated managed block in $script:ParsecConfigTxtPath"
}

function Set-ParsecRegistryPolicy {
    param([hashtable]$Settings)

    if (-not (Test-IsAdmin)) {
        Write-PCModeLog 'Registry Parsec policy skipped because this shell is not admin'
        return
    }

    try {
        New-Item -Path $script:ParsecRegistryPath -Force | Out-Null
        $backupPath = Join-Path $script:PCModeStateDir ("parsec-registry.backup-{0}.reg" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        & reg.exe export 'HKLM\SOFTWARE\Parsec' $backupPath /y *>> $script:CurrentLogPath
        Write-PCModeLog "Parsec registry policy backed up to $backupPath"

        $configuration = ($Settings.Keys | Sort-Object | ForEach-Object { "{0}={1}" -f $_, $Settings[$_] }) -join ':'
        New-ItemProperty -Path $script:ParsecRegistryPath -Name 'Configuration' -Value $configuration -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $script:ParsecRegistryPath -Name 'PCModeManagedConfiguration' -Value $configuration -PropertyType String -Force | Out-Null
        Write-PCModeLog "Parsec registry policy updated: $configuration"
    } catch {
        Write-PCModeLog "Could not write Parsec registry policy: $_"
    }
}

function Set-ParsecRemoteConfig {
    param(
        [pscustomobject]$Config,
        [int]$ServerAdminMute = 1,
        [string]$HostAudioId = ''
    )

    $settings = @{
        app_host = 1
        app_run_level = 1
        client_automatic_displays = 'false'
        client_immersive = 1
        host_full_fps = 'true'
        host_virtual_monitor_fallback = ([string][bool]$Config.EnableFallbackVirtualDisplay).ToLowerInvariant()
        server_admin_mute = $ServerAdminMute
    }

    if ([bool]$Config.EnableParsecPrivacyMode) {
        $settings.host_virtual_monitors = [int]$Config.VirtualDisplayCount
        $settings.host_privacy_mode = 1
    }

    if (-not [string]::IsNullOrWhiteSpace($HostAudioId)) {
        $settings.host_audio_id = $HostAudioId
    }

    if (Test-Path -LiteralPath $script:ParsecConfigJsonPath) {
        Backup-File -Path $script:ParsecConfigJsonPath | Out-Null
    }

    try {
        $json = $null
        if (Test-Path -LiteralPath $script:ParsecConfigJsonPath) {
            $json = Get-Content -LiteralPath $script:ParsecConfigJsonPath -Raw | ConvertFrom-Json
        }

        if ($null -eq $json -or $json.Count -lt 2) {
            $json = @(
                'See https://parsec.app/config for documentation and example. JSON must be valid before saving or file be will be erased.',
                [pscustomobject]@{}
            )
        }

        $parsecSettings = $json[1]
        foreach ($key in $settings.Keys) {
            $value = $settings[$key]
            if ($value -is [string]) {
                if ($value.ToLowerInvariant() -eq 'true') { $value = $true }
                elseif ($value.ToLowerInvariant() -eq 'false') { $value = $false }
            }
            Set-JsonSetting -Settings $parsecSettings -Name $key -Value $value
        }

        if ([bool]$Config.RemovePinnedPhysicalParsecOutputs) {
            $toRemove = @($parsecSettings.PSObject.Properties.Name | Where-Object { $_ -like 'host_output*' })
            foreach ($name in $toRemove) {
                Remove-JsonSetting -Settings $parsecSettings -Name $name
                Write-PCModeLog "Removed pinned physical Parsec output: $name"
            }
        }

        if ([string]::IsNullOrWhiteSpace($HostAudioId)) {
            Remove-JsonSetting -Settings $parsecSettings -Name 'host_audio_id'
            Write-PCModeLog 'Removed pinned Parsec host audio device so normal mode follows Windows default audio'
        }

        Remove-JsonSetting -Settings $parsecSettings -Name 'encoder_bitrate'
        Write-PCModeLog 'Removed pinned Parsec encoder bitrate so the Mbps slider stays editable'

        $json | ConvertTo-Json -Depth 12 | Out-File -LiteralPath $script:ParsecConfigJsonPath -Encoding UTF8
        Write-PCModeLog "Updated $script:ParsecConfigJsonPath"
    } catch {
        Write-PCModeLog "Could not update Parsec config.json: $_"
    }

    Set-ParsecConfigTextBlock -Settings $settings
    Set-ParsecRegistryPolicy -Settings $settings
}
