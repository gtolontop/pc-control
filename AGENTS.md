# Consignes Codex — PC Control

## Protection de la machine distante

- Le propriétaire est en vacances et dépend de cette tour à distance.
- Travailler par défaut uniquement dans ce dossier local.
- Ne jamais arrêter, hiberner, redémarrer ou mettre en veille le PC.
- Ne jamais redémarrer Cloudflared, SSH, Parsec, FanControl, `remote-wake` ou le Raspberry.
- Ne jamais modifier une tâche planifiée Windows, un service systemd, le tunnel Cloudflare,
  `/opt/remote-wake`, `/etc/remote-wake.env` ou `C:\PCMode` sans autorisation explicite.
- Toute inspection distante doit rester en lecture seule.
- Un déploiement nécessite une demande explicite, une sauvegarde et un plan de retour arrière.

## Secrets

- Ne jamais committer de token Cloudflare, clé du portail, clé SSH privée, adresse MAC privée
  ou contenu de `/etc/remote-wake.env`.
- Utiliser les fichiers `.example` et des variables d'environnement.
- Ne jamais afficher un secret dans les logs ou les réponses.

## Organisation

- `raspberry/app` est un snapshot du code actuellement déployé.
- `windows-agent` est un snapshot de `C:\PCMode`, pas l'installation active.
- `desktop-launchers` est un snapshot des lanceurs actuels.
- Les évolutions desktop doivent vivre dans un dossier dédié, sans appeler les commandes
  destructrices pendant les tests.

