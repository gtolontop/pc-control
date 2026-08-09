param(
    [switch]$Once
)

. 'C:\PCMode\remote-common.ps1'

New-PCModeLog -Name 'night-mode-watchdog' | Out-Null
Write-PCModeLog 'Night mode watchdog is intentionally disabled; hard monitor toggling caused Parsec capture freezes.'
Write-PCModeLog 'Use night-mode-on.ps1 for soft display power-off, or add a dummy plug / stable virtual display for remote-only display capture.'
exit 0
