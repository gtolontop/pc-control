$ErrorActionPreference = 'Continue'

$parsecDataDir = Join-Path $env:ProgramData 'Parsec'
$configJsonPath = Join-Path $parsecDataDir 'config.json'
$configTxtPath = Join-Path $parsecDataDir 'config.txt'
$backupDir = Join-Path $parsecDataDir 'PCModeClientBackups'

if (-not (Test-Path -LiteralPath $parsecDataDir)) {
    New-Item -ItemType Directory -Path $parsecDataDir -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
}

function Backup-ParsecFile {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path) {
        $name = Split-Path -Path $Path -Leaf
        $backup = Join-Path $backupDir ("{0}.backup-{1}" -f $name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Copy-Item -LiteralPath $Path -Destination $backup -Force
        Write-Output "Backed up $Path to $backup"
    }
}

function Set-JsonSetting {
    param(
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value
    )

    if ($Settings.PSObject.Properties[$Name]) {
        $Settings.$Name.value = $Value
    } else {
        $Settings | Add-Member -MemberType NoteProperty -Name $Name -Value ([pscustomobject]@{ value = $Value })
    }
}

Backup-ParsecFile -Path $configJsonPath
Backup-ParsecFile -Path $configTxtPath

$json = $null
if (Test-Path -LiteralPath $configJsonPath) {
    try {
        $json = Get-Content -LiteralPath $configJsonPath -Raw | ConvertFrom-Json
    } catch {
        Write-Output "Could not parse existing config.json, creating a fresh valid config: $_"
    }
}

if ($null -eq $json -or $json.Count -lt 2) {
    $json = @(
        'See https://parsec.app/config for documentation and example. JSON must be valid before saving or file be will be erased.',
        [pscustomobject]@{}
    )
}

$settings = $json[1]
Set-JsonSetting -Settings $settings -Name 'client_immersive' -Value 1
Set-JsonSetting -Settings $settings -Name 'client_automatic_displays' -Value $false
Set-JsonSetting -Settings $settings -Name 'client_windowed' -Value 0

$json | ConvertTo-Json -Depth 12 | Out-File -LiteralPath $configJsonPath -Encoding UTF8

$block = @(
    '# BEGIN PCMode managed client config',
    'client_automatic_displays = false',
    'client_immersive = 1',
    'client_windowed = 0',
    '# END PCMode managed client config'
) -join [Environment]::NewLine

$existing = ''
if (Test-Path -LiteralPath $configTxtPath) {
    $existing = Get-Content -LiteralPath $configTxtPath -Raw
}

$clean = [regex]::Replace($existing, '(?ms)# BEGIN PCMode managed client config.*?# END PCMode managed client config\s*', '')
($clean.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $block + [Environment]::NewLine) |
    Out-File -LiteralPath $configTxtPath -Encoding UTF8

Write-Output 'Parsec client settings applied: immersive both, fullscreen, no automatic extra screens.'
Write-Output 'Fully quit and reopen Parsec on this client for config file changes to apply.'
