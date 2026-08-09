# Politique de sécurité

## Données interdites dans Git

- clé Bearer du portail ;
- token ou credential Cloudflare Tunnel ;
- clé SSH privée ;
- contenu de `/etc/remote-wake.env` ;
- base de télémétrie ou journal contenant des données privées ;
- secrets copiés depuis l'historique d'un navigateur ou d'un terminal.

## Modèle de sécurité

Le navigateur communique avec le Raspberry via HTTPS et Cloudflare Tunnel. Le Raspberry
authentifie les appels, puis utilise un pont SSH à commandes autorisées vers Windows.
L'interface seule ne constitue jamais une frontière de sécurité : toute action doit aussi
être validée côté serveur et côté pont Windows.

## Signalement

Ce dépôt est privé. Signaler une vulnérabilité directement au propriétaire, sans ouvrir
d'issue publique et sans inclure de secret dans une capture ou un journal.

## Réponse à un secret exposé

1. Révoquer ou renouveler immédiatement le secret concerné.
2. Vérifier les journaux Cloudflare, Raspberry et Windows.
3. Nettoyer l'historique Git si nécessaire.
4. Ajouter une règle de prévention avant toute nouvelle publication.
