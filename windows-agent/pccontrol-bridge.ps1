<#
    PC Control — pont enrichi (session SSH, non interactive).

    Reçoit un payload JSON { "action": "...", "args": { ... } } et exécute une
    action d'une liste fermée. Deux familles :

      * Actions « système » traitées ici même (fichiers, processus, disques,
        terminal) : le pont tourne dans la session SSH, il a accès au disque et
        aux processus mais PAS au bureau interactif.

      * Actions « session » (capture d'écran, souris, clavier, volume…) qui
        exigent un bureau réel : relayées à l'agent de session via le dossier
        C:\PCMode\bridge. Pour une capture, le pont relit le JPEG écrit par
        l'agent et l'encode en base64 pour le portail (le pont ne capture jamais
        l'écran lui-même : encoder une image n'est donc pas signé antivirus).

    Aucune commande arbitraire hors de cette liste n'est possible.
#>

param(
    [string]$Payload,
    # Mode persistant : lit des lignes JSON sur stdin, répond une ligne par requête.
    # Le Raspberry garde ainsi UNE connexion SSH ouverte et supprime le coût de
    # poignée de main + démarrage de processus à chaque action (~500 ms -> ~5 ms).
    [switch]$Loop
)

$ErrorActionPreference = 'Stop'

# Sortie en UTF-8 pour que les accents des messages arrivent intacts au Raspberry.
# NE PAS toucher à InputEncoding : réaffecter l'encodage d'un stdin redirigé (pipe)
# bloque [Console]::In.ReadLine(). L'entrée (JSON du Pi) est de l'ASCII/UTF-8 que
# le lecteur par défaut gère sans problème.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$BridgeRoot = 'C:\PCMode\bridge'
$InBox = Join-Path $BridgeRoot 'in'
$OutBox = Join-Path $BridgeRoot 'out'
$LiveDir = Join-Path $BridgeRoot 'live'
$FramePath = Join-Path $LiveDir 'frame.jpg'
$FrameMeta = Join-Path $LiveDir 'frame.json'
$StreamControl = Join-Path $LiveDir 'stream.json'
$Heartbeat = Join-Path $BridgeRoot 'agent.json'
$AgentScript = 'C:\PCMode\pccontrol-agent.ps1'
$MaxTextBytes = 262144       # lecture de fichier texte : 256 Ko
$MaxDownloadBytes = 6291456  # téléchargement binaire d'un coup : 6 Mo
$MaxChunkBytes = 4194304     # bloc de transfert par morceaux : 4 Mo

foreach ($d in @($LiveDir)) { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }

# Actions qui nécessitent le bureau interactif : déléguées à l'agent de session.
$SessionActions = @(
    'Screenshot', 'ScreenInfo', 'Click', 'MoveMouse', 'Drag', 'Scroll', 'TypeText', 'SendKey',
    'Volume', 'Media', 'Lock', 'DisplaysOff', 'DisplaysOn', 'GetClipboard', 'SetClipboard',
    'WindowList', 'FocusWindow', 'CloseWindow', 'Launch', 'OpenPath', 'OpenUrl', 'Notify',
    'SessionInfo', 'LogOff', 'StreamStart', 'StreamStop', 'ConnectBack'
)

# Actions système traitées directement par le pont (accès disque/processus,
# lecture des trames d'écran écrites par le daemon de capture).
$SystemActions = @(
    'FsList', 'FsRead', 'FsWrite', 'FsDelete', 'FsMkdir', 'FsRename', 'FsDownload',
    'FsStat', 'FsDownloadChunk', 'FsWriteChunk', 'Drives', 'Processes', 'KillProcess',
    'Exec', 'BridgeStatus', 'Frame', 'ChannelInfo'
)

function Write-Json {
    param($Data)
    # Sortie UTF-8 directe (voir l'en-tête : OutputEncoding forcé). ConvertTo-Json
    # -Compress produit une seule ligne (les \r\n internes sont échappés en \n),
    # donc une réponse = une ligne. On évite toute boucle caractère par caractère :
    # pour une image base64 de 60 Ko elle coûtait ~1 s par trame.
    $json = $Data | ConvertTo-Json -Compress -Depth 8
    [Console]::Out.Write($json)
    [Console]::Out.Write("`n")
    # Flush impératif : stdout est un pipe (SSH), sinon la dernière ligne reste
    # tamponnée et le Raspberry attend indéfiniment sa fin de ligne.
    [Console]::Out.Flush()
}

function Get-Arg {
    param($Arguments, [string]$Name, $Default = $null)
    if ($null -eq $Arguments) { return $Default }
    $property = $Arguments.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

# --------------------------------------------------------------------------- #
# Relais vers l'agent de session
# --------------------------------------------------------------------------- #

function Test-AgentAlive {
    if (-not (Test-Path -LiteralPath $Heartbeat)) { return $false }
    $item = Get-Item -LiteralPath $Heartbeat -ErrorAction SilentlyContinue
    if (-not $item) { return $false }
    return ((Get-Date) - $item.LastWriteTime).TotalSeconds -lt 12
}

function Start-SessionAgent {
    try {
        Start-ScheduledTask -TaskName 'PCControl_SessionAgent' -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Invoke-SessionAction {
    param([string]$Action, $Arguments)

    $agentUp = Test-AgentAlive
    if (-not $agentUp) {
        Start-SessionAgent | Out-Null
        for ($i = 0; $i -lt 25; $i++) {
            Start-Sleep -Milliseconds 200
            if (Test-AgentAlive) { $agentUp = $true; break }
        }
    }
    if (-not $agentUp) {
        throw 'Agent de session indisponible (aucune session ouverte sur la tour ?).'
    }

    $id = [guid]::NewGuid().ToString('N')
    $request = @{ action = $Action }
    if ($null -ne $Arguments) { $request.args = $Arguments }
    # Capture : nom de trame déterministe pour retrouver le JPEG.
    if ($Action -eq 'Screenshot') {
        if ($null -eq $request.args) { $request.args = @{} }
        $request.args = $request.args | Select-Object *
    }

    $requestJson = $request | ConvertTo-Json -Compress -Depth 8
    $inPath = Join-Path $InBox "$id.json"
    $temporary = "$inPath.tmp"
    [System.IO.File]::WriteAllText($temporary, $requestJson, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $inPath -Force

    $outPath = Join-Path $OutBox "$id.json"
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $outPath) {
            $raw = Get-Content -LiteralPath $outPath -Raw -Encoding UTF8
            Remove-Item -LiteralPath $outPath -Force -ErrorAction SilentlyContinue
            $result = $raw | ConvertFrom-Json

            # Pour une capture, joindre l'image encodée (le pont ne capture pas l'écran).
            if ($Action -eq 'Screenshot' -and $result.ok -and $result.PSObject.Properties['image_file']) {
                $framePath = Join-Path $OutBox ([string]$result.image_file)
                if (Test-Path -LiteralPath $framePath) {
                    $bytes = [System.IO.File]::ReadAllBytes($framePath)
                    $output = [ordered]@{}
                    foreach ($property in $result.PSObject.Properties) { $output[$property.Name] = $property.Value }
                    $output['image'] = [Convert]::ToBase64String($bytes)
                    $output.Remove('image_file') | Out-Null
                    return [pscustomobject]$output
                }
            }
            return $result
        }
        Start-Sleep -Milliseconds 12
    }
    throw 'Délai dépassé : la session ne répond pas.'
}

# --------------------------------------------------------------------------- #
# Actions système
# --------------------------------------------------------------------------- #

function Resolve-SafePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Chemin manquant.' }
    return [System.IO.Path]::GetFullPath($Path)
}

function Invoke-FsList {
    param($Arguments)
    $path = [string](Get-Arg $Arguments 'path' '')
    if (-not $path) {
        # Racine virtuelle : les disques.
        $drives = Get-CimInstance Win32_LogicalDisk | ForEach-Object {
            @{
                name = $_.DeviceID
                path = "$($_.DeviceID)\"
                dir = $true
                size = [int64]($_.Size)
                free = [int64]($_.FreeSpace)
            }
        }
        return @{ ok = $true; path = ''; parent = $null; entries = @($drives); is_root = $true }
    }
    $full = Resolve-SafePath $path
    if (-not (Test-Path -LiteralPath $full)) { throw 'Chemin introuvable.' }
    $entries = New-Object System.Collections.ArrayList
    $items = Get-ChildItem -LiteralPath $full -Force -ErrorAction SilentlyContinue |
        Sort-Object -Property @{ Expression = { -not $_.PSIsContainer } }, Name
    foreach ($item in $items) {
        $isDir = $item.PSIsContainer
        [void]$entries.Add(@{
            name = $item.Name
            path = $item.FullName
            dir = $isDir
            size = if ($isDir) { $null } else { [int64]$item.Length }
            modified = [int][double]([DateTimeOffset]$item.LastWriteTimeUtc).ToUnixTimeSeconds()
            hidden = [bool]($item.Attributes -band [System.IO.FileAttributes]::Hidden)
        })
    }
    $parent = [System.IO.Path]::GetDirectoryName($full)
    return @{
        ok = $true
        path = $full
        parent = if ($parent) { $parent } else { '' }
        entries = @($entries.ToArray() | Select-Object -First 500)
        count = $entries.Count
    }
}

function Invoke-FsRead {
    param($Arguments)
    $full = Resolve-SafePath ([string](Get-Arg $Arguments 'path' ''))
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw 'Fichier introuvable.' }
    $length = (Get-Item -LiteralPath $full).Length
    if ($length -gt $MaxTextBytes) { throw "Fichier trop volumineux ($([math]::Round($length/1KB)) Ko) pour l'aperçu texte." }
    $bytes = [System.IO.File]::ReadAllBytes($full)
    # Heuristique binaire : présence d'octets nuls.
    if ($bytes -contains 0) { throw 'Fichier binaire : utilise le téléchargement.' }
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    return @{ ok = $true; path = $full; text = $text; bytes = $length }
}

function Invoke-FsWrite {
    param($Arguments)
    $full = Resolve-SafePath ([string](Get-Arg $Arguments 'path' ''))
    $base64 = Get-Arg $Arguments 'content_base64' $null
    if ($null -ne $base64) {
        $bytes = [Convert]::FromBase64String([string]$base64)
        [System.IO.File]::WriteAllBytes($full, $bytes)
        return @{ ok = $true; path = $full; bytes = $bytes.Length; message = 'Fichier écrit.' }
    }
    $text = [string](Get-Arg $Arguments 'text' '')
    [System.IO.File]::WriteAllText($full, $text, (New-Object System.Text.UTF8Encoding($false)))
    return @{ ok = $true; path = $full; bytes = [System.Text.Encoding]::UTF8.GetByteCount($text); message = 'Fichier écrit.' }
}

function Invoke-FsDelete {
    param($Arguments)
    $full = Resolve-SafePath ([string](Get-Arg $Arguments 'path' ''))
    if (-not (Test-Path -LiteralPath $full)) { throw 'Chemin introuvable.' }
    $recurse = [bool](Get-Arg $Arguments 'recurse' $false)
    Remove-Item -LiteralPath $full -Force -Recurse:$recurse -ErrorAction Stop
    return @{ ok = $true; path = $full; message = 'Supprimé.' }
}

function Invoke-FsMkdir {
    param($Arguments)
    $full = Resolve-SafePath ([string](Get-Arg $Arguments 'path' ''))
    New-Item -ItemType Directory -Path $full -Force | Out-Null
    return @{ ok = $true; path = $full; message = 'Dossier créé.' }
}

function Invoke-FsRename {
    param($Arguments)
    $full = Resolve-SafePath ([string](Get-Arg $Arguments 'path' ''))
    $newName = [string](Get-Arg $Arguments 'name' '')
    if (-not $newName -or $newName -match '[\\/:]') { throw 'Nouveau nom invalide.' }
    Rename-Item -LiteralPath $full -NewName $newName -ErrorAction Stop
    return @{ ok = $true; message = 'Renommé.' }
}

function Invoke-FsDownload {
    param($Arguments)
    $full = Resolve-SafePath ([string](Get-Arg $Arguments 'path' ''))
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw 'Fichier introuvable.' }
    $length = (Get-Item -LiteralPath $full).Length
    if ($length -gt $MaxDownloadBytes) { throw "Fichier trop volumineux ($([math]::Round($length/1MB,1)) Mo, max 6 Mo)." }
    $bytes = [System.IO.File]::ReadAllBytes($full)
    return @{
        ok = $true
        name = [System.IO.Path]::GetFileName($full)
        bytes = $length
        content_base64 = [Convert]::ToBase64String($bytes)
    }
}

function Invoke-Drives {
    $drives = Get-CimInstance Win32_LogicalDisk | ForEach-Object {
        $size = [int64]($_.Size)
        $free = [int64]($_.FreeSpace)
        @{
            name = $_.DeviceID
            label = $_.VolumeName
            type = switch ($_.DriveType) { 2 { 'Amovible' } 3 { 'Local' } 4 { 'Réseau' } 5 { 'CD' } default { 'Autre' } }
            size_gb = if ($size) { [math]::Round($size / 1GB, 1) } else { $null }
            free_gb = if ($free) { [math]::Round($free / 1GB, 1) } else { $null }
            used_percent = if ($size -gt 0) { [math]::Round((1 - ($free / $size)) * 100) } else { $null }
        }
    }
    return @{ ok = $true; drives = @($drives) }
}

function Invoke-Processes {
    $processes = Get-Process | Where-Object { $_.WorkingSet64 -gt 0 } |
        Sort-Object -Property WorkingSet64 -Descending | Select-Object -First 30 |
        ForEach-Object {
            @{
                pid = $_.Id
                name = $_.ProcessName
                memory_mb = [math]::Round($_.WorkingSet64 / 1MB, 1)
                window = if ($_.MainWindowTitle) { $_.MainWindowTitle } else { '' }
            }
        }
    return @{ ok = $true; processes = @($processes) }
}

function Invoke-KillProcess {
    param($Arguments)
    $processId = [int](Get-Arg $Arguments 'pid' 0)
    if ($processId -le 0) { throw 'PID invalide.' }
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if (-not $process) { throw 'Processus introuvable.' }
    $name = $process.ProcessName
    Stop-Process -Id $processId -Force -ErrorAction Stop
    return @{ ok = $true; message = "Processus $name ($processId) arrêté." }
}

function Invoke-Exec {
    param($Arguments)
    $command = [string](Get-Arg $Arguments 'command' '')
    if (-not $command.Trim()) { throw 'Commande vide.' }
    $shell = ([string](Get-Arg $Arguments 'shell' 'powershell')).ToLowerInvariant()
    $timeoutMs = [int](Get-Arg $Arguments 'timeout_ms' 45000)
    $timeoutMs = [math]::Max(1000, [math]::Min(120000, $timeoutMs))

    $info = New-Object System.Diagnostics.ProcessStartInfo
    if ($shell -eq 'cmd') {
        $info.FileName = 'cmd.exe'
        $info.Arguments = "/d /c $command"
    } else {
        $info.FileName = 'powershell.exe'
        # $ProgressPreference silencieux : sinon PowerShell pollue stderr avec du CLIXML de progression.
        $wrapped = "`$ProgressPreference='SilentlyContinue';`n$command"
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($wrapped))
        $info.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded"
    }
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $info.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $process = [System.Diagnostics.Process]::Start($info)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($timeoutMs)) {
        try { $process.Kill($true) } catch { }
        throw "Commande interrompue après $([math]::Round($timeoutMs/1000)) s."
    }
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    $limit = 20000
    if ($stdout.Length -gt $limit) { $stdout = $stdout.Substring(0, $limit) + "`n… (tronqué)" }
    if ($stderr.Length -gt $limit) { $stderr = $stderr.Substring(0, $limit) + "`n… (tronqué)" }
    return @{
        ok = ($process.ExitCode -eq 0)
        exit_code = $process.ExitCode
        stdout = $stdout
        stderr = $stderr
        message = "Sortie code $($process.ExitCode)."
    }
}

function Invoke-BridgeStatus {
    return @{
        ok = $true
        bridge = 10
        agent_alive = Test-AgentAlive
        capabilities = @($SessionActions + $SystemActions)
    }
}

function Invoke-ChannelInfo {
    # Donne au Raspberry le port + jeton du canal TCP rapide publié par l'agent.
    $info = Join-Path $BridgeRoot 'channel.json'
    if (-not (Test-Path -LiteralPath $info)) { throw 'Canal non publié (agent hors ligne ?).' }
    $data = Get-Content -LiteralPath $info -Raw -Encoding UTF8 | ConvertFrom-Json
    return @{ ok = $true; port = [int]$data.port; token = [string]$data.token }
}

function Invoke-FsStat {
    param($Arguments)
    $full = Resolve-SafePath ([string](Get-Arg $Arguments 'path' ''))
    if (-not (Test-Path -LiteralPath $full)) { throw 'Introuvable.' }
    $item = Get-Item -LiteralPath $full -Force
    $isDir = $item.PSIsContainer
    return @{
        ok = $true
        path = $full
        name = $item.Name
        dir = $isDir
        size = if ($isDir) { $null } else { [int64]$item.Length }
    }
}

function Invoke-FsDownloadChunk {
    param($Arguments)
    $full = Resolve-SafePath ([string](Get-Arg $Arguments 'path' ''))
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw 'Fichier introuvable.' }
    $offset = [int64](Get-Arg $Arguments 'offset' 0)
    $length = [int](Get-Arg $Arguments 'length' $MaxChunkBytes)
    $length = [math]::Max(1, [math]::Min($MaxChunkBytes, $length))
    $stream = [System.IO.File]::OpenRead($full)
    try {
        $total = $stream.Length
        if ($offset -ge $total) { return @{ ok = $true; offset = $offset; total = $total; eof = $true; content_base64 = '' } }
        [void]$stream.Seek($offset, [System.IO.SeekOrigin]::Begin)
        $remaining = [int][math]::Min([int64]$length, $total - $offset)
        $buffer = New-Object byte[] $remaining
        $read = $stream.Read($buffer, 0, $remaining)
        if ($read -lt $remaining) { $buffer = $buffer[0..($read - 1)] }
        return @{
            ok = $true
            offset = $offset
            read = $read
            total = $total
            eof = (($offset + $read) -ge $total)
            content_base64 = [Convert]::ToBase64String($buffer)
        }
    } finally {
        $stream.Dispose()
    }
}

function Invoke-FsWriteChunk {
    param($Arguments)
    $full = Resolve-SafePath ([string](Get-Arg $Arguments 'path' ''))
    $offset = [int64](Get-Arg $Arguments 'offset' 0)
    $bytes = [Convert]::FromBase64String([string](Get-Arg $Arguments 'content_base64' ''))
    $mode = if ($offset -eq 0) { [System.IO.FileMode]::Create } else { [System.IO.FileMode]::OpenOrCreate }
    $stream = [System.IO.File]::Open($full, $mode, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        [void]$stream.Seek($offset, [System.IO.SeekOrigin]::Begin)
        $stream.Write($bytes, 0, $bytes.Length)
    } finally {
        $stream.Dispose()
    }
    return @{ ok = $true; offset = $offset; written = $bytes.Length; next = ($offset + $bytes.Length) }
}

function Set-StreamAlive {
    param($Arguments)
    # Maintient le daemon de capture en vie et applique les réglages demandés.
    $control = @{}
    if (Test-Path -LiteralPath $StreamControl) {
        try { $control = (Get-Content -LiteralPath $StreamControl -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { $control = $null }
        if ($control) { $h = @{}; foreach ($p in $control.PSObject.Properties) { $h[$p.Name] = $p.Value }; $control = $h } else { $control = @{} }
    }
    foreach ($k in 'monitor', 'width', 'quality', 'fps') {
        $v = Get-Arg $Arguments $k $null
        if ($null -ne $v) { $control[$k] = $v }
    }
    $control['until'] = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 8
    $tmp = "$StreamControl.tmp"
    [System.IO.File]::WriteAllText($tmp, ($control | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $StreamControl -Force
}

function Invoke-Frame {
    param($Arguments)
    # Le pont lit directement la dernière trame écrite par le daemon (session 0
    # peut lire le fichier), sans passer par l'agent : latence minimale. On ne
    # renvoie l'image que si elle a changé depuis la séquence connue du client.
    Set-StreamAlive $Arguments
    if (-not (Test-Path -LiteralPath $FrameMeta)) {
        # Aucune trame encore : demander à l'agent de lancer le daemon.
        try { Invoke-SessionAction -Action 'StreamStart' -Arguments $Arguments | Out-Null } catch { }
        return @{ ok = $true; ready = $false }
    }
    $meta = $null
    try { $meta = Get-Content -LiteralPath $FrameMeta -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    if (-not $meta) { return @{ ok = $true; ready = $false } }

    $since = [int](Get-Arg $Arguments 'since' -1)
    $out = @{
        ok = $true
        ready = $true
        img_seq = [int]$meta.img_seq
        w = [int]$meta.w
        h = [int]$meta.h
        cursor = @{ x = [int]$meta.cursor.x; y = [int]$meta.cursor.y; on = [bool]$meta.cursor.on }
        monitors = $meta.monitors
    }
    if ([int]$meta.img_seq -eq $since -or -not (Test-Path -LiteralPath $FramePath)) {
        $out.changed = $false
        return $out
    }
    try {
        $out.image = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($FramePath))
        $out.changed = $true
    } catch {
        $out.changed = $false
    }
    return $out
}

# --------------------------------------------------------------------------- #
# Répartition
# --------------------------------------------------------------------------- #

function Invoke-Bridge {
    param($Request)
    $action = [string]$Request.action
    $arguments = if ($Request.PSObject.Properties['args']) { $Request.args } else { $null }

    if ($SessionActions -contains $action) {
        return Invoke-SessionAction -Action $action -Arguments $arguments
    }
    switch ($action) {
        'Frame' { return Invoke-Frame $arguments }
        'FsList' { return Invoke-FsList $arguments }
        'FsRead' { return Invoke-FsRead $arguments }
        'FsWrite' { return Invoke-FsWrite $arguments }
        'FsDelete' { return Invoke-FsDelete $arguments }
        'FsMkdir' { return Invoke-FsMkdir $arguments }
        'FsRename' { return Invoke-FsRename $arguments }
        'FsDownload' { return Invoke-FsDownload $arguments }
        'FsStat' { return Invoke-FsStat $arguments }
        'FsDownloadChunk' { return Invoke-FsDownloadChunk $arguments }
        'FsWriteChunk' { return Invoke-FsWriteChunk $arguments }
        'Drives' { return Invoke-Drives }
        'Processes' { return Invoke-Processes }
        'KillProcess' { return Invoke-KillProcess $arguments }
        'Exec' { return Invoke-Exec $arguments }
        'BridgeStatus' { return Invoke-BridgeStatus }
        'ChannelInfo' { return Invoke-ChannelInfo }
        default { return @{ ok = $false; error = "Action non autorisée : $action" } }
    }
}

if ($Loop) {
    # Canal persistant : une requête JSON par ligne, une réponse par ligne.
    [Console]::Out.Write("READY`n")
    [Console]::Out.Flush()
    while ($null -ne ($line = [Console]::In.ReadLine())) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $request = $line | ConvertFrom-Json
            $result = Invoke-Bridge $request
        } catch {
            $result = @{ ok = $false; error = $_.Exception.Message }
        }
        Write-Json $result
    }
    exit 0
}

# Mode one-shot (compatibilité / repli).
if (-not $Payload) {
    Write-Json @{ ok = $false; error = 'Payload manquant.' }
    exit 2
}
try {
    $request = $Payload | ConvertFrom-Json
} catch {
    Write-Json @{ ok = $false; error = 'Payload JSON invalide.' }
    exit 2
}
try {
    Write-Json (Invoke-Bridge $request)
    exit 0
} catch {
    Write-Json @{ ok = $false; error = $_.Exception.Message; action = [string]$request.action }
    exit 1
}
