param(
    [switch]$RestartParsec
)

. 'C:\PCMode\remote-common.ps1'

New-PCModeLog -Name 'rollback-remote-setup' | Out-Null
Write-PCModeLog 'Starting PCMode remote setup rollback'
Clear-NightModeActiveFlag

if (Test-IsAdmin) {
    Enable-PhysicalMonitors
} else {
    Write-PCModeLog 'Monitor re-enable requires admin if devices were disabled; trying display wake only'
}

Invoke-DisplayWake

try {
    $backup = Get-ChildItem -LiteralPath $script:PCModeStateDir -Filter 'config.json.backup-*' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($backup) {
        Copy-Item -LiteralPath $backup.FullName -Destination $script:ParsecConfigJsonPath -Force
        Write-PCModeLog "Restored Parsec config.json from $($backup.FullName)"
    } elseif (Test-Path -LiteralPath $script:ParsecConfigJsonPath) {
        $json = Get-Content -LiteralPath $script:ParsecConfigJsonPath -Raw | ConvertFrom-Json
        if ($json.Count -ge 2) {
            $settings = $json[1]
            foreach ($name in @('host_virtual_monitors', 'host_privacy_mode', 'host_audio_id')) {
                Remove-JsonSetting -Settings $settings -Name $name
            }
            $json | ConvertTo-Json -Depth 12 | Out-File -LiteralPath $script:ParsecConfigJsonPath -Encoding UTF8
            Write-PCModeLog 'Removed managed Parsec virtual/privacy/audio settings from config.json'
        }
    }
} catch {
    Write-PCModeLog "Could not restore Parsec config.json: $_"
}

try {
    if (Test-Path -LiteralPath $script:ParsecConfigTxtPath) {
        $begin = '# BEGIN PCMode managed remote host config'
        $end = '# END PCMode managed remote host config'
        $text = Get-Content -LiteralPath $script:ParsecConfigTxtPath -Raw
        $beginPattern = [regex]::Escape($begin)
        $endPattern = [regex]::Escape($end)
        $text = [regex]::Replace($text, "(?ms)$beginPattern.*?$endPattern\s*", '')
        $text | Out-File -LiteralPath $script:ParsecConfigTxtPath -Encoding UTF8
        Write-PCModeLog 'Removed managed block from Parsec config.txt'
    }
} catch {
    Write-PCModeLog "Could not clean Parsec config.txt: $_"
}

if (Test-IsAdmin) {
    try {
        $managed = (Get-ItemProperty -Path $script:ParsecRegistryPath -Name 'PCModeManagedConfiguration' -ErrorAction SilentlyContinue).PCModeManagedConfiguration
        if ($managed) {
            Remove-ItemProperty -Path $script:ParsecRegistryPath -Name 'Configuration' -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $script:ParsecRegistryPath -Name 'PCModeManagedConfiguration' -ErrorAction SilentlyContinue
            Write-PCModeLog 'Removed PCMode-managed Parsec registry policy'
        }
    } catch {
        Write-PCModeLog "Could not remove Parsec registry policy: $_"
    }
} else {
    Write-PCModeLog 'Registry rollback skipped because this shell is not admin'
}

Ensure-ParsecService | Out-Null

if ($RestartParsec) {
    Write-PCModeLog 'RestartParsec requested; current remote sessions may disconnect'
    try {
        Restart-Service -Name Parsec -Force -ErrorAction Stop
        Write-PCModeLog 'Parsec service restarted'
    } catch {
        Write-PCModeLog "Could not restart Parsec service: $_"
    }
}

Write-PCModeLog 'Rollback complete'
