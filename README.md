# PC Control

Copie de développement unifiée du système **GTOL Control Center**.

Cette arborescence réunit, sans modifier les installations actives :

- le portail et la passerelle Raspberry Pi actuellement déployés ;
- les services systemd et le watchdog Wake-on-LAN ;
- l'agent Windows PCMode et ses actions distantes ;
- les lanceurs historiques du Bureau ;
- une configuration Cloudflare Tunnel sans identifiants.

## Sécurité importante

Le PC est utilisé à distance. Le dépôt local n'est relié à aucun déploiement automatique.
Modifier ou tester les fichiers ici ne modifie ni `C:\PCMode`, ni le Raspberry Pi.

Ne jamais lancer depuis le projet les actions `Hibernate`, `Reboot`, arrêt, veille,
redémarrage de service ou changement de tunnel sans demande explicite du propriétaire.

## Arborescence

```text
PC-Control-Project/
├── raspberry/
│   ├── app/              # Snapshot de /opt/remote-wake
│   ├── config/           # Exemples sans secrets
│   └── systemd/          # Services et watchdog déployés
├── windows-agent/        # Snapshot des scripts actifs de C:\PCMode
├── desktop-launchers/    # Snapshot des lanceurs du Bureau
└── docs/                 # Architecture et inventaire
```

## Système actif retrouvé

- Site : `https://wake.your-script.com`
- Origine Raspberry : `http://127.0.0.1:8789`
- Application Raspberry : `/opt/remote-wake/server.py`
- Interface : `/opt/remote-wake/portal_ui.py`
- Service : `remote-wake.service`
- Surveillance : `pc-wake-watchdog.service`
- Pont Windows : SSH à commandes autorisées vers `C:\PCMode\remote-ssh-dispatch.ps1`

## Développement local

Le serveur Raspberry n'utilise que la bibliothèque standard Python. Avant tout essai,
copier `raspberry/config/remote-wake.env.example` vers un fichier local ignoré par Git
et remplacer uniquement les valeurs factices.

Le prochain chantier conseillé est de séparer l'interface HTML embarquée dans
`portal_ui.py`, d'ajouter des tests de l'API, puis de construire le client desktop.

