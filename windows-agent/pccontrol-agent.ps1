<#
    PC Control — agent de session interactive.

    Le pont SSH tourne en session 0 : il ne voit ni l'écran, ni le presse-papiers,
    ni le clavier de l'utilisateur. Cet agent tourne dans la session ouverte de
    teamr et exécute pour lui les actions qui exigent un bureau réel.

    Protocole : le pont dépose C:\PCMode\bridge\in\<id>.json, l'agent répond dans
    C:\PCMode\bridge\out\<id>.json. Aucun port réseau n'est ouvert, aucune commande
    arbitraire n'est acceptée : seules les actions listées dans Invoke-AgentAction
    sont exécutées.
#>

param([switch]$Once)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$AgentVersion = 9
$Root = 'C:\PCMode\bridge'
$InBox = Join-Path $Root 'in'
$OutBox = Join-Path $Root 'out'
$Heartbeat = Join-Path $Root 'agent.json'
$LogFile = Join-Path $Root 'agent.log'

foreach ($folder in @($Root, $InBox, $OutBox)) {
    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
}

function Write-AgentLog {
    param([string]$Message)
    try {
        $line = '{0} {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
        $item = Get-Item -LiteralPath $LogFile -ErrorAction SilentlyContinue
        if ($item -and $item.Length -gt 512KB) {
            $keep = Get-Content -LiteralPath $LogFile -Tail 400
            Set-Content -LiteralPath $LogFile -Value $keep -Encoding UTF8
        }
    } catch {
    }
}

# Une seule instance : la tâche planifiée peut être relancée par le pont.
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\PCControlSessionAgent', [ref]$createdNew)
if (-not $createdNew) {
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$nativeSource = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class PcInput
{
    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)]
    struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)]
    struct INPUT { public uint type; public INPUTUNION u; }

    const uint INPUT_MOUSE = 0;
    const uint INPUT_KEYBOARD = 1;
    const uint KEYEVENTF_KEYUP = 0x0002;
    const uint KEYEVENTF_UNICODE = 0x0004;
    const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    const uint MOUSEEVENTF_LEFTUP = 0x0004;
    const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    const uint MOUSEEVENTF_RIGHTUP = 0x0010;
    const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
    const uint MOUSEEVENTF_MIDDLEUP = 0x0040;
    const uint MOUSEEVENTF_WHEEL = 0x0800;
    const uint MOUSEEVENTF_HWHEEL = 0x01000;

    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool LockWorkStation();
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }

    static void Send(INPUT[] inputs)
    {
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
    }

    static INPUT Mouse(uint flags, uint data)
    {
        INPUT input = new INPUT();
        input.type = INPUT_MOUSE;
        input.u.mi.dwFlags = flags;
        input.u.mi.mouseData = data;
        return input;
    }

    public static void Click(string button, bool doubleClick)
    {
        uint down = MOUSEEVENTF_LEFTDOWN, up = MOUSEEVENTF_LEFTUP;
        if (button == "right") { down = MOUSEEVENTF_RIGHTDOWN; up = MOUSEEVENTF_RIGHTUP; }
        else if (button == "middle") { down = MOUSEEVENTF_MIDDLEDOWN; up = MOUSEEVENTF_MIDDLEUP; }
        int rounds = doubleClick ? 2 : 1;
        for (int i = 0; i < rounds; i++)
        {
            Send(new INPUT[] { Mouse(down, 0), Mouse(up, 0) });
            if (rounds > 1) System.Threading.Thread.Sleep(40);
        }
    }

    public static void Wheel(int amount, bool horizontal)
    {
        Send(new INPUT[] { Mouse(horizontal ? MOUSEEVENTF_HWHEEL : MOUSEEVENTF_WHEEL, unchecked((uint)amount)) });
    }

    public static void TypeText(string text)
    {
        if (string.IsNullOrEmpty(text)) return;
        INPUT[] inputs = new INPUT[text.Length * 2];
        for (int i = 0; i < text.Length; i++)
        {
            inputs[i * 2] = Key(text[i], false);
            inputs[i * 2 + 1] = Key(text[i], true);
        }
        Send(inputs);
    }

    static INPUT Key(char c, bool up)
    {
        INPUT input = new INPUT();
        input.type = INPUT_KEYBOARD;
        input.u.ki.wScan = c;
        input.u.ki.dwFlags = KEYEVENTF_UNICODE | (up ? KEYEVENTF_KEYUP : 0);
        return input;
    }

    static INPUT Vk(ushort code, bool up)
    {
        INPUT input = new INPUT();
        input.type = INPUT_KEYBOARD;
        input.u.ki.wVk = code;
        input.u.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
        return input;
    }

    public static void PressKey(ushort code, ushort[] modifiers)
    {
        int count = (modifiers == null ? 0 : modifiers.Length);
        INPUT[] inputs = new INPUT[(count + 1) * 2];
        int index = 0;
        for (int i = 0; i < count; i++) inputs[index++] = Vk(modifiers[i], false);
        inputs[index++] = Vk(code, false);
        inputs[index++] = Vk(code, true);
        for (int i = count - 1; i >= 0; i--) inputs[index++] = Vk(modifiers[i], true);
        Send(inputs);
    }

    public static void MonitorPower(int state)
    {
        IntPtr result;
        SendMessageTimeout((IntPtr)0xFFFF, 0x0112, (IntPtr)0xF170, (IntPtr)state, 0x0002, 1500, out result);
    }
}

public static class PcVolume
{
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class DeviceEnumerator { }

    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator
    {
        int NotImpl1();
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
    }

    [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice
    {
        int Activate(ref Guid id, int context, IntPtr activationParams, out IAudioEndpointVolume volume);
    }

    [Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioEndpointVolume
    {
        int RegisterControlChangeNotify(IntPtr notify);
        int UnregisterControlChangeNotify(IntPtr notify);
        int GetChannelCount(out int count);
        int SetMasterVolumeLevel(float level, ref Guid context);
        int SetMasterVolumeLevelScalar(float level, ref Guid context);
        int GetMasterVolumeLevel(out float level);
        int GetMasterVolumeLevelScalar(out float level);
        int SetChannelVolumeLevel(uint channel, float level, ref Guid context);
        int SetChannelVolumeLevelScalar(uint channel, float level, ref Guid context);
        int GetChannelVolumeLevel(uint channel, out float level);
        int GetChannelVolumeLevelScalar(uint channel, out float level);
        int SetMute(bool mute, ref Guid context);
        int GetMute(out bool mute);
    }

    static IAudioEndpointVolume Endpoint()
    {
        IMMDeviceEnumerator enumerator = (IMMDeviceEnumerator)(new DeviceEnumerator());
        IMMDevice device;
        Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(0, 1, out device));
        Guid iid = typeof(IAudioEndpointVolume).GUID;
        IAudioEndpointVolume volume;
        Marshal.ThrowExceptionForHR(device.Activate(ref iid, 23, IntPtr.Zero, out volume));
        return volume;
    }

    public static int GetLevel()
    {
        float level;
        Marshal.ThrowExceptionForHR(Endpoint().GetMasterVolumeLevelScalar(out level));
        return (int)Math.Round(level * 100);
    }

    public static void SetLevel(int percent)
    {
        if (percent < 0) percent = 0;
        if (percent > 100) percent = 100;
        Guid context = Guid.Empty;
        Marshal.ThrowExceptionForHR(Endpoint().SetMasterVolumeLevelScalar(percent / 100f, ref context));
    }

    public static bool GetMute()
    {
        bool mute;
        Marshal.ThrowExceptionForHR(Endpoint().GetMute(out mute));
        return mute;
    }

    public static void SetMute(bool mute)
    {
        Guid context = Guid.Empty;
        Marshal.ThrowExceptionForHR(Endpoint().SetMute(mute, ref context));
    }
}
'@

Add-Type -TypeDefinition $nativeSource -ErrorAction Stop
[void][PcInput]::SetProcessDPIAware()

# --------------------------------------------------------------------------- #
# Utilitaires
# --------------------------------------------------------------------------- #

$VirtualKeys = @{
    'enter' = 0x0D; 'escape' = 0x1B; 'tab' = 0x09; 'backspace' = 0x08; 'delete' = 0x2E
    'up' = 0x26; 'down' = 0x28; 'left' = 0x25; 'right' = 0x27; 'space' = 0x20
    'home' = 0x24; 'end' = 0x23; 'pageup' = 0x21; 'pagedown' = 0x22
    'win' = 0x5B; 'f1' = 0x70; 'f2' = 0x71; 'f3' = 0x72; 'f4' = 0x73; 'f5' = 0x74
    'f11' = 0x7A; 'f12' = 0x7B; 'printscreen' = 0x2C
    'volumeup' = 0xAF; 'volumedown' = 0xAE; 'volumemute' = 0xAD
    'playpause' = 0xB3; 'nexttrack' = 0xB0; 'prevtrack' = 0xB1; 'stop' = 0xB2
}

$Modifiers = @{ 'ctrl' = 0x11; 'alt' = 0x12; 'shift' = 0x10; 'win' = 0x5B }

function Get-Screens {
    $list = New-Object System.Collections.ArrayList
    $index = 0
    foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
        [void]$list.Add(@{
            index = $index
            name = $screen.DeviceName
            primary = $screen.Primary
            x = $screen.Bounds.X
            y = $screen.Bounds.Y
            width = $screen.Bounds.Width
            height = $screen.Bounds.Height
        })
        $index++
    }
    return , $list.ToArray()
}

function Get-CaptureBounds {
    param($Monitor)
    $screens = [System.Windows.Forms.Screen]::AllScreens
    if ($null -eq $Monitor -or "$Monitor" -eq 'all' -or [int]$Monitor -lt 0) {
        return [System.Windows.Forms.SystemInformation]::VirtualScreen
    }
    $index = [int]$Monitor
    if ($index -ge $screens.Count) { $index = 0 }
    return $screens[$index].Bounds
}

function Get-ArgValue {
    param($Arguments, [string]$Name, $Default = $null)
    if ($null -eq $Arguments) { return $Default }
    $property = $Arguments.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

# --------------------------------------------------------------------------- #
# Actions
# --------------------------------------------------------------------------- #

# La capture d'écran vit dans un script séparé (pccontrol-capture.ps1) : réunir
# capture d'écran et synthèse d'entrées clavier/souris dans un même script
# déclenche une signature antivirus. On délègue donc la capture à un processus
# dédié qui ne fait que ça, et on récupère le JPEG écrit sur disque.
function Invoke-Screenshot {
    param($Arguments)

    $monitor = [int](Get-ArgValue $Arguments 'monitor' -1)
    $quality = [int](Get-ArgValue $Arguments 'quality' 55)
    $width = [int](Get-ArgValue $Arguments 'width' 1280)
    $frameName = ([string](Get-ArgValue $Arguments 'frame' 'frame')) -replace '[^A-Za-z0-9_-]', ''
    if (-not $frameName) { $frameName = 'frame' }
    $framePath = Join-Path $OutBox "$frameName.jpg"

    $capture = Join-Path (Split-Path -Parent $PSCommandPath) 'pccontrol-capture.ps1'
    if (-not (Test-Path -LiteralPath $capture)) { throw 'Script de capture introuvable.' }

    $arguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $capture,
        '-Monitor', $monitor, '-Width', $width, '-Quality', $quality, '-OutPath', $framePath
    )
    $standardOut = Join-Path $OutBox "$frameName.capout"
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments `
        -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput $standardOut
    $meta = $null
    if (Test-Path -LiteralPath $standardOut) {
        try {
            $line = (Get-Content -LiteralPath $standardOut -Raw -Encoding UTF8).Trim()
            if ($line) { $meta = $line | ConvertFrom-Json }
        } catch {
        }
        Remove-Item -LiteralPath $standardOut -Force -ErrorAction SilentlyContinue
    }
    if ($process.ExitCode -ne 0 -or -not $meta -or -not (Test-Path -LiteralPath $framePath)) {
        throw 'La capture d''écran a échoué.'
    }

    return @{
        ok = $true
        image_file = "$frameName.jpg"
        content_type = 'image/jpeg'
        width = [int]$meta.width
        height = [int]$meta.height
        source_width = [int]$meta.source_width
        source_height = [int]$meta.source_height
        bytes = [int]$meta.bytes
        monitors = Get-Screens
    }
}

function Invoke-Pointer {
    param($Arguments, [string]$Kind)

    $bounds = Get-CaptureBounds (Get-ArgValue $Arguments 'monitor' 0)
    $nx = [double](Get-ArgValue $Arguments 'nx' 0.5)
    $ny = [double](Get-ArgValue $Arguments 'ny' 0.5)
    $nx = [math]::Max(0.0, [math]::Min(1.0, $nx))
    $ny = [math]::Max(0.0, [math]::Min(1.0, $ny))
    $x = [int]($bounds.X + ($nx * ($bounds.Width - 1)))
    $y = [int]($bounds.Y + ($ny * ($bounds.Height - 1)))
    [void][PcInput]::SetCursorPos($x, $y)

    if ($Kind -eq 'click') {
        $button = [string](Get-ArgValue $Arguments 'button' 'left')
        if ($button -notin @('left', 'right', 'middle')) { $button = 'left' }
        $double = [bool](Get-ArgValue $Arguments 'double' $false)
        Start-Sleep -Milliseconds 25
        [PcInput]::Click($button, $double)
        return @{ ok = $true; message = "Clic $button envoyé."; x = $x; y = $y }
    }
    return @{ ok = $true; message = 'Curseur déplacé.'; x = $x; y = $y }
}

function Invoke-Scroll {
    param($Arguments)
    $amount = [int](Get-ArgValue $Arguments 'amount' -360)
    $amount = [math]::Max(-3000, [math]::Min(3000, $amount))
    $horizontal = [bool](Get-ArgValue $Arguments 'horizontal' $false)
    [PcInput]::Wheel($amount, $horizontal)
    return @{ ok = $true; message = 'Défilement envoyé.' }
}

function Invoke-TypeText {
    param($Arguments)
    $text = [string](Get-ArgValue $Arguments 'text' '')
    if ($text.Length -gt 2000) { $text = $text.Substring(0, 2000) }
    if (-not $text) { throw 'Aucun texte à saisir.' }
    [PcInput]::TypeText($text)
    if ([bool](Get-ArgValue $Arguments 'enter' $false)) {
        Start-Sleep -Milliseconds 60
        [PcInput]::PressKey([uint16]0x0D, $null)
    }
    return @{ ok = $true; message = "$($text.Length) caractère(s) saisis." }
}

function Invoke-SendKey {
    param($Arguments)
    $name = ([string](Get-ArgValue $Arguments 'key' '')).ToLowerInvariant()
    if (-not $VirtualKeys.ContainsKey($name)) { throw "Touche inconnue : $name" }
    $modifierNames = @(Get-ArgValue $Arguments 'modifiers' @())
    $codes = New-Object System.Collections.ArrayList
    foreach ($modifier in $modifierNames) {
        $lower = ([string]$modifier).ToLowerInvariant()
        if ($Modifiers.ContainsKey($lower)) { [void]$codes.Add([uint16]$Modifiers[$lower]) }
    }
    [PcInput]::PressKey([uint16]$VirtualKeys[$name], [uint16[]]$codes.ToArray())
    return @{ ok = $true; message = "Touche $name envoyée." }
}

function Invoke-Volume {
    param($Arguments)
    $level = Get-ArgValue $Arguments 'level' $null
    $mute = Get-ArgValue $Arguments 'mute' $null
    if ($null -ne $level) { [PcVolume]::SetLevel([int]$level) }
    if ($null -ne $mute) { [PcVolume]::SetMute([bool]$mute) }
    return @{ ok = $true; volume = [PcVolume]::GetLevel(); muted = [PcVolume]::GetMute(); message = 'Volume appliqué.' }
}

function Invoke-Media {
    param($Arguments)
    $command = ([string](Get-ArgValue $Arguments 'command' 'playpause')).ToLowerInvariant()
    $map = @{ 'playpause' = 'playpause'; 'next' = 'nexttrack'; 'prev' = 'prevtrack'; 'stop' = 'stop' }
    if (-not $map.ContainsKey($command)) { throw "Commande média inconnue : $command" }
    [PcInput]::PressKey([uint16]$VirtualKeys[$map[$command]], $null)
    return @{ ok = $true; message = "Média : $command." }
}

function Get-WindowList {
    $windows = New-Object System.Collections.ArrayList
    foreach ($process in Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle }) {
        [void]$windows.Add(@{
            pid = $process.Id
            title = $process.MainWindowTitle
            process = $process.ProcessName
            handle = [string]$process.MainWindowHandle
        })
    }
    return , ($windows.ToArray() | Select-Object -First 40)
}

function Invoke-Window {
    param($Arguments, [string]$Kind)
    $processId = [int](Get-ArgValue $Arguments 'pid' 0)
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if (-not $process -or $process.MainWindowHandle -eq 0) { throw 'Fenêtre introuvable.' }
    if ($Kind -eq 'focus') {
        [void][PcInput]::ShowWindow($process.MainWindowHandle, 9)
        [void][PcInput]::SetForegroundWindow($process.MainWindowHandle)
        return @{ ok = $true; message = "Fenêtre $($process.ProcessName) au premier plan." }
    }
    [void][PcInput]::PostMessage($process.MainWindowHandle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    return @{ ok = $true; message = "Fermeture demandée pour $($process.ProcessName)." }
}

function Get-AppCatalog {
    $configPath = 'C:\PCMode\pccontrol-apps.json'
    if (Test-Path -LiteralPath $configPath) {
        try {
            return @(Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        } catch {
        }
    }
    return @()
}

function Invoke-Launch {
    param($Arguments)
    $id = [string](Get-ArgValue $Arguments 'app' '')
    $entry = Get-AppCatalog | Where-Object { $_.id -eq $id } | Select-Object -First 1
    if (-not $entry) { throw "Application non déclarée : $id" }
    if (-not (Test-Path -LiteralPath $entry.path)) { throw "Introuvable sur le disque : $($entry.path)" }
    if ($entry.PSObject.Properties['args'] -and $entry.args) {
        Start-Process -FilePath $entry.path -ArgumentList $entry.args | Out-Null
    } else {
        Start-Process -FilePath $entry.path | Out-Null
    }
    return @{ ok = $true; message = "$($entry.name) lancé." }
}

function Invoke-OpenPath {
    param($Arguments)
    $path = [string](Get-ArgValue $Arguments 'path' '')
    if (-not $path) { throw 'Chemin manquant.' }
    if (-not (Test-Path -LiteralPath $path)) { throw 'Chemin introuvable.' }
    $item = Get-Item -LiteralPath $path -Force
    if ($item.PSIsContainer) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$($item.FullName)`"" | Out-Null
    } else {
        Start-Process -FilePath 'explorer.exe' -ArgumentList "/select,`"$($item.FullName)`"" | Out-Null
    }
    return @{ ok = $true; message = 'Explorateur ouvert sur la tour.' }
}

function Invoke-OpenUrl {
    param($Arguments)
    $url = [string](Get-ArgValue $Arguments 'url' '')
    if ($url -notmatch '^https?://[^\s"'']+$') { throw 'URL invalide.' }
    Start-Process -FilePath $url | Out-Null
    return @{ ok = $true; message = 'Page ouverte sur la tour.' }
}

function Invoke-Notify {
    param($Arguments)
    $title = [string](Get-ArgValue $Arguments 'title' 'PC Control')
    $text = [string](Get-ArgValue $Arguments 'text' '')
    if (-not $text) { throw 'Message vide.' }
    $icon = New-Object System.Windows.Forms.NotifyIcon
    $icon.Icon = [System.Drawing.SystemIcons]::Information
    $icon.Visible = $true
    $icon.ShowBalloonTip(6000, $title.Substring(0, [math]::Min(60, $title.Length)),
        $text.Substring(0, [math]::Min(240, $text.Length)),
        [System.Windows.Forms.ToolTipIcon]::Info)
    Start-Sleep -Milliseconds 700
    return @{ ok = $true; message = 'Notification affichée sur la tour.' }
}

function Get-SessionSnapshot {
    $volume = $null
    $muted = $null
    try {
        $volume = [PcVolume]::GetLevel()
        $muted = [PcVolume]::GetMute()
    } catch {
    }
    $foreground = ''
    try {
        $top = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle } |
            Sort-Object -Property CPU -Descending | Select-Object -First 1
        if ($top) { $foreground = $top.MainWindowTitle }
    } catch {
    }
    return @{
        ok = $true
        agent = $AgentVersion
        volume = $volume
        muted = $muted
        monitors = Get-Screens
        window = $foreground
        apps = @(Get-AppCatalog | ForEach-Object { @{ id = $_.id; name = $_.name } })
    }
}

function Invoke-AgentAction {
    param([string]$Action, $Arguments)

    switch ($Action) {
        'Screenshot' { return Invoke-Screenshot $Arguments }
        'ScreenInfo' { return @{ ok = $true; monitors = Get-Screens } }
        'Click' { return Invoke-Pointer $Arguments 'click' }
        'MoveMouse' { return Invoke-Pointer $Arguments 'move' }
        'Scroll' { return Invoke-Scroll $Arguments }
        'TypeText' { return Invoke-TypeText $Arguments }
        'SendKey' { return Invoke-SendKey $Arguments }
        'Volume' { return Invoke-Volume $Arguments }
        'Media' { return Invoke-Media $Arguments }
        'Lock' {
            [void][PcInput]::LockWorkStation()
            return @{ ok = $true; message = 'Session Windows verrouillée.' }
        }
        'DisplaysOff' {
            [PcInput]::MonitorPower(2)
            return @{ ok = $true; message = 'Écrans éteints.' }
        }
        'DisplaysOn' {
            [PcInput]::MonitorPower(-1)
            [void][PcInput]::SetCursorPos([System.Windows.Forms.Cursor]::Position.X + 1, [System.Windows.Forms.Cursor]::Position.Y)
            return @{ ok = $true; message = 'Écrans réveillés.' }
        }
        'GetClipboard' {
            $text = Get-Clipboard -Raw -ErrorAction SilentlyContinue
            if ($null -eq $text) { $text = '' }
            if ($text.Length -gt 20000) { $text = $text.Substring(0, 20000) }
            return @{ ok = $true; text = $text }
        }
        'SetClipboard' {
            $text = [string](Get-ArgValue $Arguments 'text' '')
            Set-Clipboard -Value $text
            return @{ ok = $true; message = 'Presse-papiers de la tour mis à jour.' }
        }
        'WindowList' { return @{ ok = $true; windows = Get-WindowList } }
        'FocusWindow' { return Invoke-Window $Arguments 'focus' }
        'CloseWindow' { return Invoke-Window $Arguments 'close' }
        'Launch' { return Invoke-Launch $Arguments }
        'OpenPath' { return Invoke-OpenPath $Arguments }
        'OpenUrl' { return Invoke-OpenUrl $Arguments }
        'Notify' { return Invoke-Notify $Arguments }
        'SessionInfo' { return Get-SessionSnapshot }
        'LogOff' {
            Start-Process -FilePath 'shutdown.exe' -ArgumentList '/l' -WindowStyle Hidden | Out-Null
            return @{ ok = $true; message = 'Fermeture de session demandée.' }
        }
        default { throw "Action de session inconnue : $Action" }
    }
}

# --------------------------------------------------------------------------- #
# Boucle
# --------------------------------------------------------------------------- #

function Write-Response {
    param([string]$Id, $Payload)
    $json = $Payload | ConvertTo-Json -Depth 6 -Compress
    $temporary = Join-Path $OutBox "$Id.tmp"
    $final = Join-Path $OutBox "$Id.json"
    [System.IO.File]::WriteAllText($temporary, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $final -Force
}

function Step {
    foreach ($request in Get-ChildItem -LiteralPath $InBox -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object CreationTimeUtc) {
        $id = [System.IO.Path]::GetFileNameWithoutExtension($request.Name)
        try {
            $payload = Get-Content -LiteralPath $request.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Remove-Item -LiteralPath $request.FullName -Force -ErrorAction SilentlyContinue
            continue
        }
        Remove-Item -LiteralPath $request.FullName -Force -ErrorAction SilentlyContinue

        $action = [string]$payload.action
        try {
            $arguments = $null
            if ($payload.PSObject.Properties['args']) { $arguments = $payload.args }
            $result = Invoke-AgentAction -Action $action -Arguments $arguments
            Write-Response $id $result
        } catch {
            Write-AgentLog "ERREUR $action : $($_.Exception.Message)"
            Write-Response $id @{ ok = $false; error = $_.Exception.Message; action = $action }
        }
    }

    # Réponses jamais consommées (client parti) : on ne laisse rien traîner.
    $limit = (Get-Date).AddMinutes(-3)
    Get-ChildItem -LiteralPath $OutBox -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $limit } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

Write-AgentLog "Agent démarré (version $AgentVersion, session $((Get-Process -Id $PID).SessionId))"

if ($Once) {
    Step
    exit 0
}

$lastBeat = [datetime]::MinValue
while ($true) {
    try {
        Step
    } catch {
        Write-AgentLog "Boucle : $($_.Exception.Message)"
    }
    if (((Get-Date) - $lastBeat).TotalSeconds -ge 2) {
        $lastBeat = Get-Date
        try {
            $beat = @{
                pid = $PID
                version = $AgentVersion
                at = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            } | ConvertTo-Json -Compress
            [System.IO.File]::WriteAllText($Heartbeat, $beat, (New-Object System.Text.UTF8Encoding($false)))
        } catch {
        }
    }
    Start-Sleep -Milliseconds 120
}
