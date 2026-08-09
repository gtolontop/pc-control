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

# Sonde légère : mesure le coût pur SSH + démarrage de processus, sans WMI.
if ($requested -eq 'Ping') {
    [Console]::Out.Write('{"ok":true,"pong":true}')
    exit 0
}

# Maintient la session (donc le tunnel -L du canal rapide) ouverte jusqu'à ce que
# le Raspberry ferme la connexion. Aucun traitement : juste garder le canal vivant.
if ($requested -eq 'Hold') {
    [void][Console]::In.ReadToEnd()
    exit 0
}

# Canal rapide multiplexé : la requête JSON arrive encodée en base64 dans la
# ligne de commande (aucun stdin, compatible ControlMaster). Réservé aux petites
# requêtes (clics, trames, actions) ; les gros transferts passent par 'Invoke'.
if ($requested -like 'Run *') {
    try {
        $json = [System.Text.Encoding]::UTF8.GetString(
            [Convert]::FromBase64String($requested.Substring(4)))
    } catch {
        @{ ok = $false; error = 'Payload Run invalide.' } | ConvertTo-Json -Compress
        exit 2
    }
    & 'C:\PCMode\pccontrol-bridge.ps1' -Payload $json
    exit $LASTEXITCODE
}

if ($requested -in $legacy) {
    & 'C:\PCMode\remote-control.ps1' -Action $requested
    exit $LASTEXITCODE
}

# Canal persistant : le Raspberry garde UNE connexion SSH ouverte et pousse des
# requêtes JSON ligne par ligne. Le pont répond une ligne par requête. Supprime
# le coût de poignée de main + démarrage de processus à chaque action.
if ($requested -eq 'Session') {
    & 'C:\PCMode\pccontrol-bridge.ps1' -Loop
    exit $LASTEXITCODE
}

# Canal enrichi one-shot : sentinel « Invoke » + payload JSON sur stdin. Conservé
# comme repli si le canal persistant tombe.
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
