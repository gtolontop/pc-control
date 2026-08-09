param(
    [switch]$SkipParsecRestart,
    [switch]$SkipDdc,
    [switch]$SkipMoveWindows
)

. 'C:\PCMode\remote-common.ps1'

New-PCModeLog -Name 'remote-night-on' | Out-Null
Write-PCModeLog 'Starting remote night mode'

$config = Get-RemoteModeConfig
Save-NightModeState -Profile 'RemoteNight' | Out-Null
Set-NightModeActiveFlag -Profile 'RemoteNight'
Set-ComputerStayAwake

function Stop-AudioAntiIdleKeeper {
    $keeperScript = 'C:\PCMode\audio-anti-idle-keeper.ps1'
    $pidPath = Join-Path $script:PCModeStateDir 'audio-anti-idle-keeper.pid'

    if (Test-Path -LiteralPath $pidPath) {
        $keeperPid = [int](Get-Content -LiteralPath $pidPath -Raw -ErrorAction SilentlyContinue)
        if ($keeperPid -gt 0) {
            Stop-Process -Id $keeperPid -Force -ErrorAction SilentlyContinue
            Write-PCModeLog "Audio anti-idle keeper stopped from pid file: $keeperPid"
        }
        Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    }

    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match [regex]::Escape($keeperScript) } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            Write-PCModeLog "Audio anti-idle keeper stopped by command line: $($_.ProcessId)"
        }
}

Stop-AudioAntiIdleKeeper

function Set-RemoteNightParsecConfig {
    param([pscustomobject]$RemoteConfig)

    $virtualAudio = Get-PreferredVirtualAudioEndpoint -Config $RemoteConfig
    $localAudio = Get-PreferredLocalAudioEndpoint -Config $RemoteConfig

    if ($virtualAudio) {
        Write-PCModeLog "Virtual audio candidate found: $($virtualAudio.Name) [$($virtualAudio.MMDeviceId)]"
        Set-DefaultRenderAudioEndpoint -Endpoint $virtualAudio | Out-Null
        if ([bool]$RemoteConfig.ResetPerAppAudioRoutingInNightMode) {
            Reset-AppAudioRouting -Reason 'Remote night selected virtual audio' | Out-Null
        } else {
            Write-PCModeLog 'Per-app audio routing left untouched for stability'
        }
        $muteValue = if ([bool]$RemoteConfig.KeepHostMutedWithVirtualAudio) { 1 } else { 0 }
        Set-ParsecRemoteConfig -Config $RemoteConfig -ServerAdminMute $muteValue -HostAudioId $virtualAudio.MMDeviceId
    } elseif ($localAudio) {
        Write-PCModeLog "Stable local audio candidate found: $($localAudio.Name) [$($localAudio.MMDeviceId)]"
        Set-DefaultRenderAudioEndpoint -Endpoint $localAudio | Out-Null
        if ([bool]$RemoteConfig.ResetPerAppAudioRoutingInNightMode) {
            Reset-AppAudioRouting -Reason 'Remote night selected local audio fallback' | Out-Null
        } else {
            Write-PCModeLog 'Per-app audio routing left untouched for stability'
        }
        $muteValue = if ([bool]$RemoteConfig.KeepHostMutedWithoutVirtualAudio) { 1 } else { 0 }
        Set-ParsecRemoteConfig -Config $RemoteConfig -ServerAdminMute $muteValue -HostAudioId $localAudio.MMDeviceId
    } else {
        Write-PCModeLog 'No preferred audio endpoint found; Parsec will keep its current/default host audio device'
        $muteValue = if ([bool]$RemoteConfig.KeepHostMutedWithoutVirtualAudio) { 1 } else { 0 }
        Set-ParsecRemoteConfig -Config $RemoteConfig -ServerAdminMute $muteValue
    }
}

function Restart-ParsecWithFreshConfig {
    param([pscustomobject]$RemoteConfig)

    try {
        $service = Get-Service -Name Parsec -ErrorAction Stop
        if ($service.StartType -ne 'Automatic') {
            Set-Service -Name Parsec -StartupType Automatic -ErrorAction SilentlyContinue
        }
        if ($service.Status -ne 'Stopped') {
            Write-PCModeLog 'Stopping Parsec before config write; remote clients will need to reconnect'
            Stop-Service -Name Parsec -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
        }
    } catch {
        Write-PCModeLog "Could not stop Parsec before config write: $_"
    }

    Set-RemoteNightParsecConfig -RemoteConfig $RemoteConfig

    try {
        Start-Service -Name Parsec -ErrorAction Stop
        Write-PCModeLog 'Parsec service started with fresh remote-night config'
        Start-Sleep -Seconds 4
    } catch {
        Write-PCModeLog "Could not start Parsec after config write: $_"
    }
}

function Move-VisibleWindowsToPrimaryDisplay {
    Add-Type -AssemblyName System.Windows.Forms

    if (-not ('PCMode.WindowMover' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace PCMode {
    public sealed class WindowInfo {
        public IntPtr Handle { get; set; }
        public string Title { get; set; }
        public string ClassName { get; set; }
        public int Left { get; set; }
        public int Top { get; set; }
        public int Right { get; set; }
        public int Bottom { get; set; }
    }

    public static class WindowMover {
        private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential)]
        private struct Rect {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [DllImport("user32.dll")]
        private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool IsIconic(IntPtr hWnd);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

        [DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr hWnd, out Rect lpRect);

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

        public static WindowInfo[] GetWindows() {
            var windows = new List<WindowInfo>();
            EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
                if (!IsWindowVisible(hWnd) || IsIconic(hWnd)) {
                    return true;
                }

                var title = new StringBuilder(512);
                GetWindowText(hWnd, title, title.Capacity);
                if (title.Length == 0) {
                    return true;
                }

                var className = new StringBuilder(256);
                GetClassName(hWnd, className, className.Capacity);
                string cls = className.ToString();
                if (cls == "Shell_TrayWnd" || cls == "Progman" || cls == "WorkerW") {
                    return true;
                }

                Rect rect;
                if (!GetWindowRect(hWnd, out rect)) {
                    return true;
                }

                int width = rect.Right - rect.Left;
                int height = rect.Bottom - rect.Top;
                if (width < 80 || height < 80) {
                    return true;
                }

                windows.Add(new WindowInfo {
                    Handle = hWnd,
                    Title = title.ToString(),
                    ClassName = cls,
                    Left = rect.Left,
                    Top = rect.Top,
                    Right = rect.Right,
                    Bottom = rect.Bottom
                });
                return true;
            }, IntPtr.Zero);
            return windows.ToArray();
        }

        public static bool Move(IntPtr hWnd, int x, int y, int width, int height) {
            const uint SWP_NOZORDER = 0x0004;
            const uint SWP_NOACTIVATE = 0x0010;
            return SetWindowPos(hWnd, IntPtr.Zero, x, y, width, height, SWP_NOZORDER | SWP_NOACTIVATE);
        }
    }
}
'@
    }

    $primary = [System.Windows.Forms.Screen]::PrimaryScreen
    $work = $primary.WorkingArea
    $moved = 0
    $offset = 0

    foreach ($window in [PCMode.WindowMover]::GetWindows()) {
        $centerX = [int](($window.Left + $window.Right) / 2)
        $centerY = [int](($window.Top + $window.Bottom) / 2)
        $onPrimary = $centerX -ge $primary.Bounds.Left -and
            $centerX -le $primary.Bounds.Right -and
            $centerY -ge $primary.Bounds.Top -and
            $centerY -le $primary.Bounds.Bottom

        if ($onPrimary) {
            continue
        }

        $width = [Math]::Min($window.Right - $window.Left, $work.Width)
        $height = [Math]::Min($window.Bottom - $window.Top, $work.Height)
        $x = $work.Left + 24 + $offset
        $y = $work.Top + 24 + $offset

        if (($x + $width) -gt $work.Right) { $x = $work.Left + 24 }
        if (($y + $height) -gt $work.Bottom) { $y = $work.Top + 24 }

        if ([PCMode.WindowMover]::Move($window.Handle, $x, $y, $width, $height)) {
            $moved++
            $offset = ($offset + 28) % 196
            Write-PCModeLog "Moved window to primary display: $($window.Title)"
        }
    }

    Write-PCModeLog "Visible windows moved to primary display: $moved"
}

if ($SkipParsecRestart) {
    Ensure-ParsecService | Out-Null
    Set-RemoteNightParsecConfig -RemoteConfig $config
    Write-PCModeLog 'Parsec restart skipped by parameter'
} else {
    Restart-ParsecWithFreshConfig -RemoteConfig $config
}

if (-not $SkipMoveWindows) {
    Move-VisibleWindowsToPrimaryDisplay
} else {
    Write-PCModeLog 'Window move skipped by parameter'
}

if (-not $SkipDdc) {
    $ddcScript = 'C:\PCMode\ddc-monitor-power.ps1'
    if (Test-Path -LiteralPath $ddcScript) {
        Write-PCModeLog 'Requesting DDC monitor off; this should not wake from Parsec mouse input'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ddcScript -Action Off *>> $script:CurrentLogPath
        Write-PCModeLog "DDC monitor off exit=$LASTEXITCODE"

        $keeperScript = 'C:\PCMode\ddc-night-keeper.ps1'
        if (Test-Path -LiteralPath $keeperScript) {
            Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $keeperScript, '-IntervalSeconds', '2') -WindowStyle Hidden
            Write-PCModeLog 'DDC night keeper started'
        } else {
            Write-PCModeLog 'DDC night keeper script missing'
        }
    } else {
        Write-PCModeLog 'DDC monitor power script missing; remote-night will not use Windows display-off fallback'
    }
} else {
    Write-PCModeLog 'DDC monitor off skipped by parameter'
}

Write-PCModeLog 'Remote night mode complete'
