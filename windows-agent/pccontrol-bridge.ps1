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

param([Parameter(Mandatory = $true)][string]$Payload)

$ErrorActionPreference = 'Stop'

$BridgeRoot = 'C:\PCMode\bridge'
$InBox = Join-Path $BridgeRoot 'in'
$OutBox = Join-Path $BridgeRoot 'out'
$Heartbeat = Join-Path $BridgeRoot 'agent.json'
$AgentScript = 'C:\PCMode\pccontrol-agent.ps1'
$MaxTextBytes = 262144      # lecture de fichier texte : 256 Ko
$MaxDownloadBytes = 6291456 # téléchargement binaire : 6 Mo

# Actions qui nécessitent le bureau interactif : déléguées à l'agent de session.
$SessionActions = @(
    'Screenshot', 'ScreenInfo', 'Click', 'MoveMouse', 'Scroll', 'TypeText', 'SendKey',
    'Volume', 'Media', 'Lock', 'DisplaysOff', 'DisplaysOn', 'GetClipboard', 'SetClipboard',
    'WindowList', 'FocusWindow', 'CloseWindow', 'Launch', 'OpenPath', 'OpenUrl', 'Notify',
    'SessionInfo', 'LogOff'
)

# Actions système traitées directement par le pont.
$SystemActions = @(
    'FsList', 'FsRead', 'FsWrite', 'FsDelete', 'FsMkdir', 'FsRename', 'FsDownload',
    'Drives', 'Processes', 'KillProcess', 'Exec', 'BridgeStatus'
)

function Write-Json {
    param($Data)
    # Échappe tout caractère non ASCII en \uXXXX : le flux SSH Windows n'est pas
    # garanti UTF-8, le portail doit toujours recevoir du JSON décodable.
    $json = $Data | ConvertTo-Json -Compress -Depth 8
    $builder = [System.Text.StringBuilder]::new()
    foreach ($char in $json.ToCharArray()) {
        $code = [int]$char
        if ($code -lt 32 -or $code -gt 126) {
            [void]$builder.Append(('\u{0:x4}' -f $code))
        } else {
            [void]$builder.Append($char)
        }
    }
    [Console]::Out.Write($builder.ToString())
    [Console]::Out.Write("`n")
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
            Start-Sleep -Milliseconds 30
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
        Start-Sleep -Milliseconds 100
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
        bridge = 9
        agent_alive = Test-AgentAlive
        capabilities = @($SessionActions + $SystemActions)
    }
}

# --------------------------------------------------------------------------- #
# Répartition
# --------------------------------------------------------------------------- #

try {
    $request = $Payload | ConvertFrom-Json
} catch {
    Write-Json @{ ok = $false; error = 'Payload JSON invalide.' }
    exit 2
}

$action = [string]$request.action
$arguments = if ($request.PSObject.Properties['args']) { $request.args } else { $null }

try {
    if ($SessionActions -contains $action) {
        $result = Invoke-SessionAction -Action $action -Arguments $arguments
        Write-Json $result
        exit 0
    }

    switch ($action) {
        'FsList' { Write-Json (Invoke-FsList $arguments) }
        'FsRead' { Write-Json (Invoke-FsRead $arguments) }
        'FsWrite' { Write-Json (Invoke-FsWrite $arguments) }
        'FsDelete' { Write-Json (Invoke-FsDelete $arguments) }
        'FsMkdir' { Write-Json (Invoke-FsMkdir $arguments) }
        'FsRename' { Write-Json (Invoke-FsRename $arguments) }
        'FsDownload' { Write-Json (Invoke-FsDownload $arguments) }
        'Drives' { Write-Json (Invoke-Drives) }
        'Processes' { Write-Json (Invoke-Processes) }
        'KillProcess' { Write-Json (Invoke-KillProcess $arguments) }
        'Exec' { Write-Json (Invoke-Exec $arguments) }
        'BridgeStatus' { Write-Json (Invoke-BridgeStatus) }
        default {
            Write-Json @{ ok = $false; error = "Action non autorisée : $action" }
            exit 2
        }
    }
    exit 0
} catch {
    Write-Json @{ ok = $false; error = $_.Exception.Message; action = $action }
    exit 1
}
