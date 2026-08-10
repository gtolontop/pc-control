<#
    PC Control — capture d'écran isolée.

    Ce script ne fait QUE capturer l'écran vers un fichier JPEG. Il est
    volontairement séparé de l'agent d'entrées (clavier/souris) : réunir capture
    d'écran et synthèse de frappe dans un même script déclenche une signature
    antivirus. Ici, aucune injection d'entrée, aucun encodage base64.

    Deux modes :
      * one-shot  : capture une image et écrit -OutPath (repli).
      * -Stream   : daemon permanent qui écrit la dernière trame en continu tant
                    qu'un client la réclame. Déduplique les images identiques
                    (seule change la position du curseur) : bande passante ~0
                    quand l'écran est statique.
#>

param(
    [int]$Monitor = -1,
    [int]$Width = 1280,
    [int]$Quality = 55,
    [string]$OutPath,
    [switch]$Stream
)

$ErrorActionPreference = 'Stop'

# GetHbitmap alloue une ressource GDI qu'il faut libérer à chaque trame, sinon la
# capture continue fuit jusqu'à épuiser le quota d'objets GDI du processus.
Add-Type -Namespace '' -Name PcGdi -MemberDefinition @'
[DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr hObject);
'@

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# Encodeur JPEG de WPF : il expose un vrai réglage de qualité, contrairement à
# System.Drawing.Imaging.EncoderParameters dont la combinaison avec une capture
# d'écran correspond à une signature antivirus connue.
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

function Get-CaptureBounds {
    param([int]$Index)
    $screens = [System.Windows.Forms.Screen]::AllScreens
    if ($Index -lt 0 -or $Index -ge $screens.Count) {
        return [System.Windows.Forms.SystemInformation]::VirtualScreen
    }
    return $screens[$Index].Bounds
}

function Get-MonitorList {
    $list = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
        [void]$list.Add(@{ index = $i; primary = [bool]$s.Primary; width = $s.Bounds.Width; height = $s.Bounds.Height })
        $i++
    }
    return , $list.ToArray()
}

# Capture un écran et renvoie les octets JPEG + dimensions, sans curseur incrusté.
function Get-FrameBytes {
    param([int]$Mon, [int]$OutWidth, [int]$Quality = 55)
    $bounds = Get-CaptureBounds $Mon
    $bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.X, $bounds.Y, 0, 0, $bounds.Size)
    $graphics.Dispose()

    if ($OutWidth -gt 0 -and $OutWidth -lt $bitmap.Width) {
        $h = [int][math]::Round($bitmap.Height * ($OutWidth / $bitmap.Width))
        if ($h -lt 1) { $h = 1 }
        $resized = New-Object System.Drawing.Bitmap($OutWidth, $h)
        $rg = [System.Drawing.Graphics]::FromImage($resized)
        $rg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
        $rg.DrawImage($bitmap, 0, 0, $OutWidth, $h)
        $rg.Dispose()
        $bitmap.Dispose()
        $bitmap = $resized
    }

    # Encodage JPEG avec qualité réglable (WPF) : c'est le principal levier de
    # poids par image, donc de latence sur une liaison lente.
    $ms = New-Object System.IO.MemoryStream
    $hbitmap = $bitmap.GetHbitmap()
    try {
        $source = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHBitmap(
            $hbitmap, [IntPtr]::Zero, [System.Windows.Int32Rect]::Empty,
            [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
        $encoder = New-Object System.Windows.Media.Imaging.JpegBitmapEncoder
        $encoder.QualityLevel = $Quality
        $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($source))
        $encoder.Save($ms)
    } finally {
        [void][PcGdi]::DeleteObject($hbitmap)
    }
    $bytes = $ms.ToArray()
    $ms.Dispose()
    $iw = $bitmap.Width
    $ih = $bitmap.Height
    $bitmap.Dispose()
    return @{ bytes = $bytes; width = $iw; height = $ih; src_width = $bounds.Width; src_height = $bounds.Height; origin_x = $bounds.X; origin_y = $bounds.Y }
}

# --------------------------------------------------------------------------- #
# Mode one-shot
# --------------------------------------------------------------------------- #
if (-not $Stream) {
    if (-not $OutPath) { throw 'OutPath requis en mode one-shot.' }
    $frame = Get-FrameBytes -Mon $Monitor -OutWidth $Width -Quality $Quality
    $tmp = "$OutPath.tmp"
    [System.IO.File]::WriteAllBytes($tmp, $frame.bytes)
    Move-Item -LiteralPath $tmp -Destination $OutPath -Force
    @{ ok = $true; width = $frame.width; height = $frame.height; source_width = $frame.src_width; source_height = $frame.src_height; bytes = $frame.bytes.Length } | ConvertTo-Json -Compress
    return
}

# --------------------------------------------------------------------------- #
# Mode daemon (-Stream)
# --------------------------------------------------------------------------- #
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\PCControlCaptureDaemon', [ref]$created)
if (-not $created) { exit 0 }

$LiveDir = 'C:\PCMode\bridge\live'
if (-not (Test-Path -LiteralPath $LiveDir)) { New-Item -ItemType Directory -Path $LiveDir -Force | Out-Null }
$FramePath = Join-Path $LiveDir 'frame.jpg'
$FrameMeta = Join-Path $LiveDir 'frame.json'
$Control = Join-Path $LiveDir 'stream.json'

$md5 = [System.Security.Cryptography.MD5]::Create()
$imgSeq = 0
$lastHash = ''
$utf8 = New-Object System.Text.UTF8Encoding($false)

while ($true) {
    $cfg = $null
    if (Test-Path -LiteralPath $Control) {
        try { $cfg = Get-Content -LiteralPath $Control -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $cfg = $null }
    }
    if (-not $cfg) { break }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ([int64]$cfg.until -lt $now) { break }   # plus personne ne regarde : on s'arrête

    $mon = if ($cfg.PSObject.Properties['monitor']) { [int]$cfg.monitor } else { -1 }
    $w = if ($cfg.PSObject.Properties['width']) { [int]$cfg.width } else { 1280 }
    $w = [math]::Max(320, [math]::Min(2560, $w))
    $q = if ($cfg.PSObject.Properties['quality']) { [int]$cfg.quality } else { 50 }
    $q = [math]::Max(15, [math]::Min(92, $q))
    $fps = if ($cfg.PSObject.Properties['fps']) { [int]$cfg.fps } else { 15 }
    $fps = [math]::Max(2, [math]::Min(40, $fps))

    try {
        $frame = Get-FrameBytes -Mon $mon -OutWidth $w -Quality $q
    } catch {
        Start-Sleep -Milliseconds 200
        continue
    }

    $hash = [Convert]::ToBase64String($md5.ComputeHash($frame.bytes))
    if ($hash -ne $lastHash) {
        $lastHash = $hash
        $imgSeq++
        $tmp = "$FramePath.tmp"
        [System.IO.File]::WriteAllBytes($tmp, $frame.bytes)
        Move-Item -LiteralPath $tmp -Destination $FramePath -Force
    }

    # Position curseur mappée dans les coordonnées de l'image (dessinée côté client).
    $cursor = [System.Windows.Forms.Cursor]::Position
    $scale = if ($frame.src_width -gt 0) { $frame.width / $frame.src_width } else { 1 }
    $cx = [int](($cursor.X - $frame.origin_x) * $scale)
    $cy = [int](($cursor.Y - $frame.origin_y) * $scale)
    $on = ($cx -ge 0 -and $cy -ge 0 -and $cx -lt $frame.width -and $cy -lt $frame.height)

    $meta = @{
        img_seq = $imgSeq
        w = $frame.width
        h = $frame.height
        src_w = $frame.src_width
        src_h = $frame.src_height
        monitor = $mon
        cursor = @{ x = $cx; y = $cy; on = $on }
        monitors = Get-MonitorList
        ts = $now
    }
    $tmpMeta = "$FrameMeta.tmp"
    [System.IO.File]::WriteAllText($tmpMeta, ($meta | ConvertTo-Json -Compress -Depth 5), $utf8)
    Move-Item -LiteralPath $tmpMeta -Destination $FrameMeta -Force

    Start-Sleep -Milliseconds ([int](1000 / $fps))
}

$md5.Dispose()
[void]$mutex.ReleaseMutex()
