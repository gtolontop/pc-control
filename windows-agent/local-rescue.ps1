param(
    [switch]$SkipScreenWake,
    [switch]$StartKeeper,
    [ValidateRange(1,100)]
    [int]$TargetVolumePercent = 50
)

. 'C:\PCMode\remote-common.ps1'

New-PCModeLog -Name 'local-rescue' | Out-Null
Write-PCModeLog 'Starting local rescue mode'

function Stop-DdcNightKeeper {
    $pidPath = Join-Path $script:PCModeStateDir 'ddc-night-keeper.pid'

    if (Test-Path -LiteralPath $pidPath) {
        $keeperPid = [int](Get-Content -LiteralPath $pidPath -Raw -ErrorAction SilentlyContinue)
        if ($keeperPid -gt 0) {
            Stop-Process -Id $keeperPid -Force -ErrorAction SilentlyContinue
            Write-PCModeLog "Stopped DDC night keeper from pid file: $keeperPid"
        }
        Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    }

    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'ddc-night-keeper\.ps1' } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            Write-PCModeLog "Stopped DDC night keeper by command line: $($_.ProcessId)"
        }
}

function Disable-WindowsAudioDucking {
    $audioKey = 'HKCU:\Software\Microsoft\Multimedia\Audio'
    New-Item -Path $audioKey -Force | Out-Null
    New-ItemProperty -Path $audioKey -Name 'UserDuckingPreference' -Value 3 -PropertyType DWord -Force | Out-Null
    Write-PCModeLog 'Windows communication ducking disabled for current user'
}

function Set-AudioStablePowerSettings {
    $settings = @(
        @('/setacvalueindex', 'SCHEME_CURRENT', '501a4d13-42af-4429-9fd1-a8218c268e20', 'ee12f906-d277-404b-b6da-e5fa1a576df5', '0'),
        @('/setacvalueindex', 'SCHEME_CURRENT', '2a737441-1930-4402-8d77-b2bebba308a3', '48e6b7a6-50f5-4782-a5d4-53bb8f07e226', '0'),
        @('/setacvalueindex', 'SCHEME_CURRENT', '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1', '12bbebe6-58d6-4636-95bb-3217ef867c1a', '0'),
        @('/setactive', 'SCHEME_CURRENT')
    )

    foreach ($args in $settings) {
        & powercfg.exe @args *>> $script:CurrentLogPath
        Write-PCModeLog "powercfg $($args -join ' ') exit=$LASTEXITCODE"
    }
}

function Start-AudioAntiIdleKeeper {
    $keeperScript = 'C:\PCMode\audio-anti-idle-keeper.ps1'
    if (-not (Test-Path -LiteralPath $keeperScript)) {
        Write-PCModeLog 'Audio anti-idle keeper script missing'
        return
    }

    $existing = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match [regex]::Escape($keeperScript) } |
        Select-Object -First 1

    if ($existing) {
        Write-PCModeLog "Audio anti-idle keeper already running: pid=$($existing.ProcessId)"
        return
    }

    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $keeperScript, '-IntervalSeconds', '10') -WindowStyle Hidden
    Write-PCModeLog 'Audio anti-idle keeper started'
}

function Normalize-CurrentAudioSessions {
    param([int]$TargetVolumePercent = 50)

    if ('PCMode.AudioSessionTools' -as [type]) {
        [PCMode.AudioSessionTools]::NormalizeDefaultRenderSessions($TargetVolumePercent) | ForEach-Object { Write-PCModeLog $_ }
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace PCMode {
    public enum SessionDataFlow {
        Render = 0,
        Capture = 1,
        All = 2
    }

    public enum SessionRole {
        Console = 0,
        Multimedia = 1,
        Communications = 2
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    public class SessionMMDeviceEnumerator {}

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface ISessionMMDeviceEnumerator {
        int EnumAudioEndpoints(SessionDataFlow dataFlow, int stateMask, out IntPtr devices);
        int GetDefaultAudioEndpoint(SessionDataFlow dataFlow, SessionRole role, out ISessionMMDevice endpoint);
        int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out ISessionMMDevice endpoint);
        int RegisterEndpointNotificationCallback(IntPtr client);
        int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface ISessionMMDevice {
        int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object interfacePointer);
        int OpenPropertyStore(int accessMode, out IntPtr properties);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        int GetState(out int state);
    }

    [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioSessionManager2 {
        int GetAudioSessionControl(IntPtr audioSessionGuid, int streamFlags, out IntPtr sessionControl);
        int GetSimpleAudioVolume(IntPtr audioSessionGuid, int streamFlags, out IntPtr audioVolume);
        int GetSessionEnumerator(out IAudioSessionEnumerator sessionEnumerator);
        int RegisterSessionNotification(IntPtr sessionNotification);
        int UnregisterSessionNotification(IntPtr sessionNotification);
        int RegisterDuckNotification([MarshalAs(UnmanagedType.LPWStr)] string sessionId, IntPtr duckNotification);
        int UnregisterDuckNotification(IntPtr duckNotification);
    }

    [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioSessionEnumerator {
        int GetCount(out int sessionCount);
        int GetSession(int sessionIndex, out IAudioSessionControl sessionControl);
    }

    [ComImport, Guid("F4B1A599-7266-4319-A8CA-E70ACB11E8CD"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioSessionControl {
        int GetState(out int state);
        int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string displayName);
        int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string displayName, ref Guid eventContext);
        int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string iconPath);
        int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string iconPath, ref Guid eventContext);
        int GetGroupingParam(out Guid groupingParam);
        int SetGroupingParam(ref Guid groupingParam, ref Guid eventContext);
        int RegisterAudioSessionNotification(IntPtr client);
        int UnregisterAudioSessionNotification(IntPtr client);
    }

    [ComImport, Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface ISimpleAudioVolume {
        int SetMasterVolume(float level, ref Guid eventContext);
        int GetMasterVolume(out float level);
        int SetMute(bool isMuted, ref Guid eventContext);
        int GetMute(out bool isMuted);
    }

    [ComImport, Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioSessionControl2 {
        int GetState(out int state);
        int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string displayName);
        int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string displayName, ref Guid eventContext);
        int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string iconPath);
        int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string iconPath, ref Guid eventContext);
        int GetGroupingParam(out Guid groupingParam);
        int SetGroupingParam(ref Guid groupingParam, ref Guid eventContext);
        int RegisterAudioSessionNotification(IntPtr client);
        int UnregisterAudioSessionNotification(IntPtr client);
        int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string sessionId);
        int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string sessionInstanceId);
        int GetProcessId(out uint processId);
        int IsSystemSoundsSession();
        int SetDuckingPreference(bool optOut);
    }

    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioEndpointVolume {
        int RegisterControlChangeNotify(IntPtr client);
        int UnregisterControlChangeNotify(IntPtr client);
        int GetChannelCount(out int count);
        int SetMasterVolumeLevel(float level, ref Guid eventContext);
        int SetMasterVolumeLevelScalar(float level, ref Guid eventContext);
        int GetMasterVolumeLevel(out float level);
        int GetMasterVolumeLevelScalar(out float level);
        int SetChannelVolumeLevel(int channel, float level, ref Guid eventContext);
        int SetChannelVolumeLevelScalar(int channel, float level, ref Guid eventContext);
        int GetChannelVolumeLevel(int channel, out float level);
        int GetChannelVolumeLevelScalar(int channel, out float level);
        int SetMute(bool isMuted, ref Guid eventContext);
        int GetMute(out bool isMuted);
        int GetVolumeStepInfo(out uint step, out uint stepCount);
        int VolumeStepUp(ref Guid eventContext);
        int VolumeStepDown(ref Guid eventContext);
        int QueryHardwareSupport(out uint hardwareSupportMask);
        int GetVolumeRange(out float minDb, out float maxDb, out float incrementDb);
    }

    public static class AudioSessionTools {
        private const int CLSCTX_ALL = 23;

        public static string[] NormalizeDefaultRenderSessions(int targetVolumePercent) {
            var output = new System.Collections.Generic.List<string>();
            var eventContext = Guid.Empty;
            float targetVolume = Math.Max(0.01f, Math.Min(1.0f, targetVolumePercent / 100.0f));
            var enumerator = (ISessionMMDeviceEnumerator)(new SessionMMDeviceEnumerator());
            ISessionMMDevice device = null;

            try {
                int hr = enumerator.GetDefaultAudioEndpoint(SessionDataFlow.Render, SessionRole.Multimedia, out device);
                if (hr != 0) {
                    Marshal.ThrowExceptionForHR(hr);
                }

                string deviceId = "";
                device.GetId(out deviceId);

                object endpointVolumeObject;
                Guid endpointVolumeGuid = typeof(IAudioEndpointVolume).GUID;
                hr = device.Activate(ref endpointVolumeGuid, CLSCTX_ALL, IntPtr.Zero, out endpointVolumeObject);
                if (hr == 0 && endpointVolumeObject != null) {
                    var endpointVolume = (IAudioEndpointVolume)endpointVolumeObject;
                    bool muted = false;
                    float level = 0;
                    endpointVolume.GetMute(out muted);
                    endpointVolume.GetMasterVolumeLevelScalar(out level);
                    if (muted) {
                        endpointVolume.SetMute(false, ref eventContext);
                        output.Add("Default endpoint unmuted");
                    }
                    if (Math.Abs(level - targetVolume) > 0.01f) {
                        endpointVolume.SetMasterVolumeLevelScalar(targetVolume, ref eventContext);
                        output.Add(String.Format("Default endpoint volume set from {0}% to {1}%", Math.Round(level * 100), targetVolumePercent));
                    } else {
                        output.Add(String.Format("Default endpoint volume already {0}%", Math.Round(level * 100)));
                    }
                    Marshal.ReleaseComObject(endpointVolume);
                }

                object managerObject;
                Guid managerGuid = typeof(IAudioSessionManager2).GUID;
                hr = device.Activate(ref managerGuid, CLSCTX_ALL, IntPtr.Zero, out managerObject);
                if (hr != 0) {
                    Marshal.ThrowExceptionForHR(hr);
                }

                var manager = (IAudioSessionManager2)managerObject;
                IAudioSessionEnumerator sessionEnumerator;
                hr = manager.GetSessionEnumerator(out sessionEnumerator);
                if (hr != 0) {
                    Marshal.ThrowExceptionForHR(hr);
                }

                int count = 0;
                sessionEnumerator.GetCount(out count);
                int changed = 0;

                for (int i = 0; i < count; i++) {
                    IAudioSessionControl sessionControl;
                    if (sessionEnumerator.GetSession(i, out sessionControl) != 0 || sessionControl == null) {
                        continue;
                    }

                    string displayName = "";
                    sessionControl.GetDisplayName(out displayName);

                    var sessionControl2 = sessionControl as IAudioSessionControl2;
                    if (sessionControl2 != null) {
                        uint processId = 0;
                        sessionControl2.GetProcessId(out processId);
                        if (sessionControl2.SetDuckingPreference(true) == 0) {
                            output.Add(String.Format("Duck opt-out enabled for session pid={0} name={1}", processId, String.IsNullOrWhiteSpace(displayName) ? "(no name)" : displayName));
                        }
                    }

                    var simpleVolume = sessionControl as ISimpleAudioVolume;
                    if (simpleVolume != null) {
                        float level = 0;
                        bool muted = false;
                        simpleVolume.GetMasterVolume(out level);
                        simpleVolume.GetMute(out muted);
                        if (muted) {
                            simpleVolume.SetMute(false, ref eventContext);
                            changed++;
                        }
                        if (level < 0.99f) {
                            simpleVolume.SetMasterVolume(1.0f, ref eventContext);
                            changed++;
                        }
                    }

                    Marshal.ReleaseComObject(sessionControl);
                }

                output.Add(String.Format("Normalized audio sessions on {0}: {1} change(s)", deviceId, changed));
                Marshal.ReleaseComObject(sessionEnumerator);
                Marshal.ReleaseComObject(manager);
            } finally {
                if (device != null) {
                    Marshal.ReleaseComObject(device);
                }
                Marshal.ReleaseComObject(enumerator);
            }

            return output.ToArray();
        }
    }
}
'@

    [PCMode.AudioSessionTools]::NormalizeDefaultRenderSessions($TargetVolumePercent) | ForEach-Object { Write-PCModeLog $_ }
}

Stop-DdcNightKeeper
Clear-NightModeActiveFlag
Ensure-ParsecService | Out-Null
Disable-WindowsAudioDucking
Set-AudioStablePowerSettings

$currentDefault = Get-DefaultRenderAudioEndpoint
if ($currentDefault) {
    Set-DefaultRenderAudioEndpoint -Endpoint $currentDefault | Out-Null
}

Normalize-CurrentAudioSessions -TargetVolumePercent $TargetVolumePercent
if ($StartKeeper) {
    Start-AudioAntiIdleKeeper
} else {
    Write-PCModeLog 'Audio anti-idle keeper left disabled'
}

$config = Get-RemoteModeConfig
Set-ParsecRemoteConfig -Config $config -ServerAdminMute 0

if (-not $SkipScreenWake) {
    $ddcScript = 'C:\PCMode\ddc-monitor-power.ps1'
    if (Test-Path -LiteralPath $ddcScript) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ddcScript -Action On *>> $script:CurrentLogPath
        Write-PCModeLog "DDC monitor on exit=$LASTEXITCODE"
    }

    & DisplaySwitch.exe /extend *>> $script:CurrentLogPath
    Write-PCModeLog "DisplaySwitch /extend exit=$LASTEXITCODE"
    Invoke-DisplayWake
}

Write-PCModeLog 'Local rescue mode complete'
