<#
    PC Control — fonctions système partagées.

    Dot-sourcé par l'agent de session (canal LAN direct, ~10 ms) ET par le pont SSH
    (repli). Ces fonctions ne font QUE du disque / des processus : aucune capture
    d'écran, aucune synthèse d'entrée, aucun encodage base64 — c'est ce qui permet
    de les charger dans l'agent sans déclencher de signature antivirus.

    Les transferts binaires (FsDownload / FsWrite, qui encodent en base64) restent
    volontairement côté pont uniquement.
#>

function Get-FsArg {
    param($Arguments, [string]$Name, $Default = $null)
    if ($null -eq $Arguments) { return $Default }
    $property = $Arguments.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

function Resolve-FsPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Chemin manquant.' }
    return [System.IO.Path]::GetFullPath($Path)
}

function Invoke-FsListShared {
    param($Arguments)
    $path = [string](Get-FsArg $Arguments 'path' '')
    if (-not $path) {
        $roots = New-Object System.Collections.ArrayList
        foreach ($drive in (Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue)) {
            [void]$roots.Add(@{
                name = $drive.DeviceID
                path = "$($drive.DeviceID)\"
                dir = $true
                size = [int64]$drive.Size
                free = [int64]$drive.FreeSpace
            })
        }
        return @{ ok = $true; path = ''; parent = $null; entries = @($roots.ToArray()); is_root = $true }
    }

    $full = Resolve-FsPath $path
    if (-not (Test-Path -LiteralPath $full)) { throw 'Chemin introuvable.' }

    # Enumeration .NET directe : nettement plus rapide que Get-ChildItem sur les
    # gros dossiers, et on lit les attributs sans repasser par le provider.
    # NB : pas de [System.IO.EnumerationOptions] ici, ce type n'existe pas dans le
    # .NET Framework de Windows PowerShell 5.1 qui exécute l'agent.
    $entries = New-Object System.Collections.ArrayList
    $directory = New-Object System.IO.DirectoryInfo($full)
    $found = @()
    try {
        $found = $directory.EnumerateFileSystemInfos('*', [System.IO.SearchOption]::TopDirectoryOnly)
    } catch {
        throw "Dossier illisible : $($_.Exception.Message)"
    }
    foreach ($item in $found) {
        $isDir = [bool]($item.Attributes -band [System.IO.FileAttributes]::Directory)
        $size = $null
        if (-not $isDir) { try { $size = [int64]$item.Length } catch { $size = $null } }
        [void]$entries.Add(@{
            name = $item.Name
            path = $item.FullName
            dir = $isDir
            size = $size
            modified = [int][double]([DateTimeOffset]$item.LastWriteTimeUtc).ToUnixTimeSeconds()
            hidden = [bool]($item.Attributes -band [System.IO.FileAttributes]::Hidden)
        })
        if ($entries.Count -ge 1500) { break }
    }

    $sorted = @($entries.ToArray() | Sort-Object -Property @{ Expression = { -not $_.dir } }, @{ Expression = { $_.name } })
    $parent = [System.IO.Path]::GetDirectoryName($full)
    return @{
        ok = $true
        path = $full
        parent = if ($parent) { $parent } else { '' }
        entries = $sorted
        count = $sorted.Count
    }
}

function Invoke-FsStatShared {
    param($Arguments)
    $full = Resolve-FsPath ([string](Get-FsArg $Arguments 'path' ''))
    if (-not (Test-Path -LiteralPath $full)) { throw 'Introuvable.' }
    $item = Get-Item -LiteralPath $full -Force
    $isDir = [bool]$item.PSIsContainer
    return @{
        ok = $true
        path = $full
        name = $item.Name
        dir = $isDir
        size = if ($isDir) { $null } else { [int64]$item.Length }
    }
}

function Invoke-FsDeleteShared {
    param($Arguments)
    $full = Resolve-FsPath ([string](Get-FsArg $Arguments 'path' ''))
    if (-not (Test-Path -LiteralPath $full)) { throw 'Chemin introuvable.' }
    $recurse = [bool](Get-FsArg $Arguments 'recurse' $false)
    Remove-Item -LiteralPath $full -Force -Recurse:$recurse -ErrorAction Stop
    return @{ ok = $true; path = $full; message = 'Supprimé.' }
}

function Invoke-FsMkdirShared {
    param($Arguments)
    $full = Resolve-FsPath ([string](Get-FsArg $Arguments 'path' ''))
    New-Item -ItemType Directory -Path $full -Force | Out-Null
    return @{ ok = $true; path = $full; message = 'Dossier créé.' }
}

function Invoke-FsRenameShared {
    param($Arguments)
    $full = Resolve-FsPath ([string](Get-FsArg $Arguments 'path' ''))
    $newName = [string](Get-FsArg $Arguments 'name' '')
    if (-not $newName -or $newName -match '[\\/:*?"<>|]') { throw 'Nouveau nom invalide.' }
    Rename-Item -LiteralPath $full -NewName $newName -ErrorAction Stop
    return @{ ok = $true; message = 'Renommé.' }
}

function Invoke-DrivesShared {
    $drives = New-Object System.Collections.ArrayList
    foreach ($drive in (Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue)) {
        $size = [int64]$drive.Size
        $free = [int64]$drive.FreeSpace
        [void]$drives.Add(@{
            name = $drive.DeviceID
            label = [string]$drive.VolumeName
            type = switch ([int]$drive.DriveType) { 2 { 'Amovible' } 3 { 'Local' } 4 { 'Réseau' } 5 { 'CD' } default { 'Autre' } }
            size_gb = if ($size -gt 0) { [math]::Round($size / 1GB, 1) } else { $null }
            free_gb = if ($size -gt 0) { [math]::Round($free / 1GB, 1) } else { $null }
            used_percent = if ($size -gt 0) { [math]::Round((1 - ($free / $size)) * 100) } else { $null }
        })
    }
    return @{ ok = $true; drives = @($drives.ToArray()) }
}

function Invoke-ProcessesShared {
    $list = New-Object System.Collections.ArrayList
    $processes = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.WorkingSet64 -gt 0 } |
        Sort-Object -Property WorkingSet64 -Descending |
        Select-Object -First 30
    foreach ($process in $processes) {
        $title = ''
        try { $title = [string]$process.MainWindowTitle } catch { $title = '' }
        [void]$list.Add(@{
            pid = $process.Id
            name = $process.ProcessName
            memory_mb = [math]::Round($process.WorkingSet64 / 1MB, 1)
            window = $title
        })
    }
    return @{ ok = $true; processes = @($list.ToArray()) }
}

function Invoke-KillProcessShared {
    param($Arguments)
    $processId = [int](Get-FsArg $Arguments 'pid' 0)
    if ($processId -le 0) { throw 'PID invalide.' }
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if (-not $process) { throw 'Processus introuvable.' }
    $name = $process.ProcessName
    Stop-Process -Id $processId -Force -ErrorAction Stop
    return @{ ok = $true; message = "Processus $name ($processId) arrêté." }
}
