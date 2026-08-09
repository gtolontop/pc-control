# Architecture actuelle

```text
Téléphone / navigateur (PWA installée)
        |
        | HTTPS + clé Bearer
        v
Cloudflare Tunnel
  wake.your-script.com
        |
        | 127.0.0.1:8789
        v
Raspberry Pi
  remote-wake/server.py
        |
        +-- Wake-on-LAN vers la tour
        +-- sondes de disponibilité, historique SQLite, audit
        +-- SSH (clé dédiée) vers le pont Windows
             |     * verbes historiques : ssh <Verbe>
             |     * canal riche       : ssh Invoke + payload JSON sur stdin
             v
Windows OpenSSH
  remote-ssh-dispatch.ps1  (commande forcée)
        |
        +-- Verbe historique -> remote-control.ps1 (Parsec, FanControl, alim…)
        +-- Invoke -> pccontrol-bridge.ps1
                 |
                 +-- Actions système (session SSH) : fichiers, disques,
                 |   processus, terminal PowerShell/cmd
                 +-- Actions bureau : relayées à l'agent de session
                          |
                          v
                 pccontrol-agent.ps1  (tâche PCControl_SessionAgent, session interactive)
                     +-- capture d'écran (délègue à pccontrol-capture.ps1)
                     +-- souris, clavier, volume, média, verrouillage
                     +-- fenêtres, presse-papiers, lancement d'apps
```

## Canaux de commande

- **Verbes historiques** (`Status`, `ShareParsec`, `RepairParsec`, `Normal`,
  `Night`, `LaunchCodex`, `RepairFans`, `Hibernate`, `Reboot`) : inchangés, une
  commande SSH sans paramètre. Endpoints `/api/status`, `/api/control`, `/api/wake`.
- **Canal riche** `/api/action` : `{ action, args }` relayé au pont via la commande
  SSH forcée `Invoke`, le payload JSON transitant par l'entrée standard. Liste
  blanche stricte appliquée côté Raspberry (`RICH_ACTIONS`) puis côté Windows
  (`pccontrol-bridge.ps1`).

## Agent de session

Le pont SSH tourne en session non interactive : il n'a ni écran, ni presse-papiers,
ni clavier. `pccontrol-agent.ps1` tourne dans la session ouverte de l'utilisateur
(tâche planifiée `PCControl_SessionAgent`, déclenchée à l'ouverture de session) et
exécute les actions qui exigent un vrai bureau. Le pont communique avec lui par un
dossier de files d'attente (`C:\PCMode\bridge\in` / `out`), jamais par le réseau.

## Contrainte antivirus (important)

Réunir dans un même script PowerShell une **capture d'écran** et une **synthèse de
frappe clavier/souris** déclenche une signature AMSI de Windows Defender. Deux
règles en découlent :

- La capture est isolée dans `pccontrol-capture.ps1` (aucune injection d'entrée).
- Le JPEG est écrit sur disque puis encodé en base64 par le pont (qui, lui, ne
  capture jamais l'écran) : capture + base64 dans le même script est aussi signé.
- Le réglage fin de qualité JPEG via `EncoderParameters` est également signé ; on
  maîtrise le poids par la résolution et la qualité GDI+ par défaut.

## Frontières de sécurité

- Le portail exige une clé Bearer comparée en temps constant côté Raspberry.
- Le tunnel masque l'origine et n'expose pas le port 8789.
- Le pont Windows n'accepte qu'une liste fermée d'actions ; toute autre commande
  SSH est rejetée.
- Les actions d'alimentation demandent une confirmation dans l'interface.
- Le terminal distant et la suppression de fichiers ne sont accessibles qu'après
  authentification par la clé unique.
- Le service Raspberry reste isolé par les protections systemd.
