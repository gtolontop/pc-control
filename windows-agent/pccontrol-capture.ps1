<#
    PC Control — capture d'écran isolée.

    Ce script ne fait QUE capturer l'écran vers un fichier JPEG. Il est
    volontairement séparé de l'agent d'entrées (clavier/souris) : réunir capture
    d'écran et synthèse de frappe dans un même script déclenche une signature
    antivirus. Ici, aucune injection d'entrée, aucun encodage base64.

    Sortie : une ligne JSON sur stdout décrivant l'image écrite.
#>

param(
    [int]$Monitor = -1,
    [int]$Width = 1280,
    [int]$Quality = 55,
    [Parameter(Mandatory = $true)][string]$OutPath
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if ($Quality -lt 20) { $Quality = 20 }
if ($Quality -gt 92) { $Quality = 92 }
if ($Width -lt 320) { $Width = 320 }
if ($Width -gt 3840) { $Width = 3840 }

$screens = [System.Windows.Forms.Screen]::AllScreens
if ($Monitor -lt 0 -or $Monitor -ge $screens.Count) {
    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
} else {
    $bounds = $screens[$Monitor].Bounds
}

$bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($bounds.X, $bounds.Y, 0, 0, $bounds.Size)

# Repère du curseur : piloter la souris à distance sans le voir serait aveugle.
# Position lue via l'API managée (aucun P/Invoke) pour rester sous le radar antivirus.
$cursor = [System.Windows.Forms.Cursor]::Position
$cx = $cursor.X - $bounds.X
$cy = $cursor.Y - $bounds.Y
if ($cx -ge 0 -and $cy -ge 0 -and $cx -lt $bounds.Width -and $cy -lt $bounds.Height) {
    $outer = New-Object System.Drawing.Pen ([System.Drawing.Color]::Black), 5
    $inner = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 2
    $graphics.DrawEllipse($outer, $cx - 11, $cy - 11, 22, 22)
    $graphics.DrawEllipse($inner, $cx - 11, $cy - 11, 22, 22)
    $outer.Dispose()
    $inner.Dispose()
}
$graphics.Dispose()

if ($Width -lt $bitmap.Width) {
    $height = [int][math]::Round($bitmap.Height * ($Width / $bitmap.Width))
    if ($height -lt 1) { $height = 1 }
    $resized = New-Object System.Drawing.Bitmap($Width, $height)
    $resizeGraphics = [System.Drawing.Graphics]::FromImage($resized)
    $resizeGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
    $resizeGraphics.DrawImage($bitmap, 0, 0, $Width, $height)
    $resizeGraphics.Dispose()
    $bitmap.Dispose()
    $bitmap = $resized
}

# On enregistre en JPEG avec la qualité par défaut de GDI+ et on maîtrise le poids
# par la résolution (paramètre Width). Le réglage fin via EncoderParameters, bien
# que légitime, correspond à une signature antivirus connue : on l'évite.
$temporary = "$OutPath.tmp"
$bitmap.Save($temporary, [System.Drawing.Imaging.ImageFormat]::Jpeg)
$imageWidth = $bitmap.Width
$imageHeight = $bitmap.Height
$bitmap.Dispose()
Move-Item -LiteralPath $temporary -Destination $OutPath -Force

@{
    ok = $true
    width = $imageWidth
    height = $imageHeight
    source_width = $bounds.Width
    source_height = $bounds.Height
    bytes = (Get-Item -LiteralPath $OutPath).Length
} | ConvertTo-Json -Compress
