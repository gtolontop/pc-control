# PC Control — agent Windows (contrôle total distant)

Trois scripts ajoutent au pont SSH le pilotage complet de la tour depuis le
téléphone. Ils vivent dans `C:\PCMode`.

## Fichiers

- `pccontrol-agent.ps1` — tourne dans la **session interactive** de l'utilisateur
  (tâche planifiée `PCControl_SessionAgent`). Traite les actions qui exigent un vrai
  bureau : clic/souris, clavier, volume (CoreAudio), touches média, verrouillage,
  écrans on/off, presse-papiers, fenêtres, lancement d'apps, notifications. Écoute
  une file de requêtes dans `C:\PCMode\bridge\in`, répond dans `...\out`.
- `pccontrol-capture.ps1` — **capture d'écran isolée** (aucune injection d'entrée).
  Écrit un JPEG. Séparé volontairement : capture + synthèse de frappe dans un même
  script déclenche une signature Windows Defender.
- `pccontrol-bridge.ps1` — reçoit un payload JSON `{ action, args }` du Raspberry via
  la commande SSH forcée `Invoke`. Traite les actions **système** (fichiers, disques,
  processus, terminal) et **relaie** les actions de bureau à l'agent de session.
- `pccontrol-apps.json` — catalogue des applications lançables (id, nom, chemin).
  Éditable à la main pour ajouter des apps.

## Installation / mise à jour

Copier les scripts dans `C:\PCMode`, puis, dans une session utilisateur (pas besoin
d'administrateur) :

```powershell
$agent = 'C:\PCMode\pccontrol-agent.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$agent`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName 'PCControl_SessionAgent' -Action $action `
    -Trigger $trigger -Settings $settings -Principal $principal -Force
Start-ScheduledTask -TaskName 'PCControl_SessionAgent'
```

`remote-ssh-dispatch.ps1` route : verbes historiques vers `remote-control.ps1`,
le canal `Run <base64>` et `Invoke` (stdin) vers `pccontrol-bridge.ps1`.

## Canal direct LAN (vitesse)

Pour éviter la lenteur du SSH sur cette tour, l'agent se connecte en **TCP direct**
au Raspberry sur le réseau local (le Pi le lui demande via l'action `ConnectBack`).
Toutes les actions bureau et les trames passent alors par ce socket persistant :
~8 ms par entrée, ~26 img/s pour l'écran. Aucun port entrant n'est ouvert sur la
tour ; c'est l'agent qui se connecte au Pi, avec un jeton dérivé de la clé Bearer.
Voir `docs/ARCHITECTURE.md`.

## Vérification

```powershell
# Agent vivant ?
Get-Content C:\PCMode\bridge\agent.json

# Test hors ligne d'une action (simule le pont)
$env:SSH_ORIGINAL_COMMAND = 'Invoke'
'{"action":"BridgeStatus"}' | powershell -NoProfile -File C:\PCMode\remote-ssh-dispatch.ps1
```

## Note antivirus

Ces scripts sont conçus pour ne PAS déclencher AMSI : capture et entrées séparées,
pas d'encodage base64 côté capture, pas de `EncoderParameters` de qualité JPEG.
Ne pas réunir ces éléments dans un seul fichier lors d'une future modification.
