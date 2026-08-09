# Architecture actuelle

```text
Téléphone / navigateur
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
        +-- sondes de disponibilité et historique SQLite
        +-- SSH avec clé et commande Windows forcée
                    |
                    v
Windows OpenSSH
  remote-ssh-dispatch.ps1
        |
        +-- liste blanche d'actions
        +-- remote-control.ps1
        +-- PCMode / Parsec / FanControl / télémétrie
```

## Frontières de sécurité existantes

- Le portail exige une clé Bearer comparée côté Raspberry.
- Le tunnel masque l'origine et n'expose pas directement le port 8789.
- Le pont Windows n'accepte qu'une liste fixe de commandes.
- Les actions d'alimentation demandent une confirmation dans l'interface.
- Le service Raspberry est isolé par les protections systemd.

## Évolution vers un projet complet

1. Conserver le serveur déployé comme référence stable.
2. Extraire le HTML/CSS/JavaScript de `portal_ui.py` vers un frontend testable.
3. Formaliser le contrat API et ajouter des tests sans accès matériel.
4. Ajouter une application desktop utilisant le même contrat API.
5. Créer des installateurs idempotents Windows et Raspberry.
6. Déployer uniquement après validation locale et sauvegarde distante.

