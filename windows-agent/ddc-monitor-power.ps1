param(
    [ValidateSet('Query', 'Off', 'On', 'Raw')]
    [string]$Action = 'Query',

    [ValidateRange(0, 5)]
    [int]$RawValue = 1
)

$ErrorActionPreference = 'Continue'

. 'C:\PCMode\remote-common.ps1'

New-PCModeLog -Name 'ddc-monitor-power' | Out-Null
Write-PCModeLog "DDC monitor power action requested: $Action"

if (-not ('PCMode.DdcMonitorPower' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace PCMode {
    public sealed class DdcMonitorState {
        public string Description { get; set; }
        public bool Supported { get; set; }
        public uint CurrentValue { get; set; }
        public uint MaximumValue { get; set; }
        public int LastError { get; set; }
    }

    public sealed class DdcSetResult {
        public string Description { get; set; }
        public uint DesiredValue { get; set; }
        public bool Success { get; set; }
        public int LastError { get; set; }
    }

    public static class DdcMonitorPower {
        private const byte PowerModeVcpCode = 0xD6;

        private delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, ref Rect lprcMonitor, IntPtr dwData);

        [StructLayout(LayoutKind.Sequential)]
        private struct Rect {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct PhysicalMonitor {
            public IntPtr Handle;

            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string Description;
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);

        [DllImport("dxva2.dll", SetLastError = true)]
        private static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, out uint numberOfPhysicalMonitors);

        [DllImport("dxva2.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint physicalMonitorArraySize, [Out] PhysicalMonitor[] physicalMonitorArray);

        [DllImport("dxva2.dll", SetLastError = true)]
        private static extern bool DestroyPhysicalMonitors(uint physicalMonitorArraySize, PhysicalMonitor[] physicalMonitorArray);

        [DllImport("dxva2.dll", SetLastError = true)]
        private static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr monitorHandle, byte vcpCode, out uint vcpCodeType, out uint currentValue, out uint maximumValue);

        [DllImport("dxva2.dll", SetLastError = true)]
        private static extern bool SetVCPFeature(IntPtr monitorHandle, byte vcpCode, uint newValue);

        public static DdcMonitorState[] QueryPower() {
            var states = new List<DdcMonitorState>();

            EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, delegate(IntPtr hMonitor, IntPtr hdcMonitor, ref Rect rect, IntPtr data) {
                var monitors = GetPhysicalMonitors(hMonitor);
                try {
                foreach (var monitor in monitors) {
                    uint type;
                    uint current;
                    uint maximum;
                    bool supported = GetVCPFeatureAndVCPFeatureReply(monitor.Handle, PowerModeVcpCode, out type, out current, out maximum);
                    states.Add(new DdcMonitorState {
                        Description = monitor.Description,
                        Supported = supported,
                        CurrentValue = supported ? current : 0,
                        MaximumValue = supported ? maximum : 0,
                        LastError = supported ? 0 : Marshal.GetLastWin32Error()
                    });
                }
                } finally {
                    DestroyMonitorArray(monitors);
                }

                return true;
            }, IntPtr.Zero);

            return states.ToArray();
        }

        public static DdcSetResult[] SetPower(uint value) {
            var results = new List<DdcSetResult>();

            EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, delegate(IntPtr hMonitor, IntPtr hdcMonitor, ref Rect rect, IntPtr data) {
                var monitors = GetPhysicalMonitors(hMonitor);
                try {
                foreach (var monitor in monitors) {
                    bool success = SetVCPFeature(monitor.Handle, PowerModeVcpCode, value);
                    results.Add(new DdcSetResult {
                        Description = monitor.Description,
                        DesiredValue = value,
                        Success = success,
                        LastError = success ? 0 : Marshal.GetLastWin32Error()
                    });
                }
                } finally {
                    DestroyMonitorArray(monitors);
                }

                return true;
            }, IntPtr.Zero);

            return results.ToArray();
        }

        public static DdcSetResult[] SetPowerOffSmart() {
            var results = new List<DdcSetResult>();

            EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, delegate(IntPtr hMonitor, IntPtr hdcMonitor, ref Rect rect, IntPtr data) {
                var monitors = GetPhysicalMonitors(hMonitor);
                try {
                foreach (var monitor in monitors) {
                    uint desired = 4;
                    uint type;
                    uint current;
                    uint maximum;
                    bool supported = GetVCPFeatureAndVCPFeatureReply(monitor.Handle, PowerModeVcpCode, out type, out current, out maximum);
                    if (supported && maximum >= 5) {
                        desired = 5;
                    }

                    bool success = SetVCPFeature(monitor.Handle, PowerModeVcpCode, desired);
                    results.Add(new DdcSetResult {
                        Description = monitor.Description,
                        DesiredValue = desired,
                        Success = success,
                        LastError = success ? 0 : Marshal.GetLastWin32Error()
                    });
                }
                } finally {
                    DestroyMonitorArray(monitors);
                }

                return true;
            }, IntPtr.Zero);

            return results.ToArray();
        }

        private static PhysicalMonitor[] GetPhysicalMonitors(IntPtr hMonitor) {
            uint count;
            if (!GetNumberOfPhysicalMonitorsFromHMONITOR(hMonitor, out count) || count == 0) {
                return new PhysicalMonitor[0];
            }

            var monitors = new PhysicalMonitor[count];
            if (!GetPhysicalMonitorsFromHMONITOR(hMonitor, count, monitors)) {
                return new PhysicalMonitor[0];
            }

            return monitors;
        }

        private static void DestroyMonitorArray(PhysicalMonitor[] monitors) {
            if (monitors != null && monitors.Length > 0) {
                DestroyPhysicalMonitors((uint)monitors.Length, monitors);
            }
        }
    }
}
'@
}

function Write-DdcRows {
    param([object[]]$Rows)

    foreach ($row in $Rows) {
        Write-PCModeLog ($row | ConvertTo-Json -Compress)
    }

    $Rows | Format-Table -AutoSize
}

switch ($Action) {
    'Query' {
        $rows = [PCMode.DdcMonitorPower]::QueryPower()
        Write-DdcRows -Rows $rows
    }
    'Off' {
        # VCP D6 value 4 is the usual off value. Some monitors advertise max 5 and ignore 4, so those get 5 only.
        $rows = [PCMode.DdcMonitorPower]::SetPowerOffSmart()
        Write-DdcRows -Rows $rows
    }
    'On' {
        # VCP D6 value 1 is "on" for standard DDC/CI monitor power mode.
        $rows = [PCMode.DdcMonitorPower]::SetPower(1)
        Write-DdcRows -Rows $rows
    }
    'Raw' {
        # Raw test mode exists for emergency/manual DDC checks. Normal wake always uses value 1.
        $rows = [PCMode.DdcMonitorPower]::SetPower([uint32]$RawValue)
        Write-DdcRows -Rows $rows
    }
}

Write-PCModeLog "DDC monitor power action complete: $Action"
