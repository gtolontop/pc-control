param(
    [ValidateRange(3,300)]
    [int]$IntervalSeconds = 10
)

$ErrorActionPreference = 'Continue'

$baseDir = 'C:\PCMode'
$stateDir = Join-Path $baseDir 'state'
$logDir = Join-Path $baseDir 'logs'
$pidPath = Join-Path $stateDir 'audio-anti-idle-keeper.pid'
$logPath = Join-Path $logDir 'last-audio-anti-idle-keeper.log'

New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

function Write-KeeperLog {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
    $line | Out-File -LiteralPath $logPath -Append -Encoding UTF8
}

"=== audio anti-idle keeper $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -LiteralPath $logPath -Encoding UTF8

$existing = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ProcessId -ne $PID -and
        $_.CommandLine -match [regex]::Escape('C:\PCMode\audio-anti-idle-keeper.ps1')
    } |
    Select-Object -First 1

if ($existing) {
    Write-KeeperLog "Another audio anti-idle keeper is already running: pid=$($existing.ProcessId)"
    exit 0
}

$PID | Out-File -LiteralPath $pidPath -Encoding ASCII

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace PCModeAntiIdle {
    public enum DataFlow {
        Render = 0,
        Capture = 1,
        All = 2
    }

    public enum Role {
        Console = 0,
        Multimedia = 1,
        Communications = 2
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    public class MMDeviceEnumerator {}

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDeviceEnumerator {
        int EnumAudioEndpoints(DataFlow dataFlow, int stateMask, out IntPtr devices);
        int GetDefaultAudioEndpoint(DataFlow dataFlow, Role role, out IMMDevice endpoint);
        int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice endpoint);
        int RegisterEndpointNotificationCallback(IntPtr client);
        int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDevice {
        int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object interfacePointer);
        int OpenPropertyStore(int accessMode, out IntPtr properties);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        int GetState(out int state);
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

    public static class AudioNudge {
        private const int CLSCTX_ALL = 23;

        public static string NudgeDefaultRenderEndpoint() {
            var eventContext = Guid.Empty;
            var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumerator());
            IMMDevice device = null;

            try {
                int hr = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia, out device);
                if (hr != 0) {
                    Marshal.ThrowExceptionForHR(hr);
                }

                string id = "";
                device.GetId(out id);

                object volumeObject;
                Guid volumeGuid = typeof(IAudioEndpointVolume).GUID;
                hr = device.Activate(ref volumeGuid, CLSCTX_ALL, IntPtr.Zero, out volumeObject);
                if (hr != 0) {
                    Marshal.ThrowExceptionForHR(hr);
                }

                var volume = (IAudioEndpointVolume)volumeObject;
                float scalar = 0;
                volume.GetMasterVolumeLevelScalar(out scalar);
                volume.SetMasterVolumeLevelScalar(scalar, ref eventContext);
                Marshal.ReleaseComObject(volume);

                return String.Format("{0} {1}%", id, Math.Round(scalar * 100));
            } finally {
                if (device != null) {
                    Marshal.ReleaseComObject(device);
                }
                Marshal.ReleaseComObject(enumerator);
            }
        }
    }
}
'@

Write-KeeperLog "Started audio anti-idle keeper, interval=${IntervalSeconds}s"
$cycle = 0

while ($true) {
    try {
        New-Item -Path 'HKCU:\Software\Microsoft\Multimedia\Audio' -Force | Out-Null
        New-ItemProperty -Path 'HKCU:\Software\Microsoft\Multimedia\Audio' -Name 'UserDuckingPreference' -Value 3 -PropertyType DWord -Force | Out-Null

        $result = [PCModeAntiIdle.AudioNudge]::NudgeDefaultRenderEndpoint()
        if (($cycle % 6) -eq 0) {
            Write-KeeperLog "Audio endpoint nudged: $result"
        }
    } catch {
        Write-KeeperLog "Audio endpoint nudge failed: $_"
    }

    $cycle++
    Start-Sleep -Seconds $IntervalSeconds
}
