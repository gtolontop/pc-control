$ErrorActionPreference = 'Stop'

# Verbes historiques : commande unique, aucun paramètre. Conservés tels quels pour
# ne pas déstabiliser le pilotage Parsec / FanControl / alimentation existant.
$legacy = @(
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

if ($requested -in $legacy) {
    & 'C:\PCMode\remote-control.ps1' -Action $requested
    exit $LASTEXITCODE
}

# Canal enrichi : le portail envoie le sentinel « Invoke » et pousse le payload
# JSON { action, args } sur l'entrée standard (aucune limite de longueur, contrairement
# à la ligne de commande). La liste blanche réelle est appliquée par le pont.
if ($requested -eq 'Invoke') {
    $payload = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($payload)) {
        @{ ok = $false; error = 'Payload vide.' } | ConvertTo-Json -Compress
        exit 2
    }
    & 'C:\PCMode\pccontrol-bridge.ps1' -Payload $payload
    exit $LASTEXITCODE
}

@{ ok = $false; error = 'Commande non autorisée.' } | ConvertTo-Json -Compress
exit 2
