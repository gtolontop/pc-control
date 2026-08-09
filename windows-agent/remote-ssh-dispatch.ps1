$ErrorActionPreference = 'Stop'

$allowed = @(
    'Status',
    'ShareParsec',
    'RepairParsec',
    'Normal',
    'Night',
    'LaunchCodex',
    'RepairFans',
    'Hibernate',
    'Reboot'
)

$requested = $env:SSH_ORIGINAL_COMMAND
if ($requested -notin $allowed) {
    @{ ok = $false; error = 'Commande non autorisée.' } |
        ConvertTo-Json -Compress
    exit 2
}

& 'C:\PCMode\remote-control.ps1' -Action $requested
exit $LASTEXITCODE
