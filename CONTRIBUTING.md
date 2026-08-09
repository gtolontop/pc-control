# Contribuer à PC Control

## Principe principal

Le dépôt est une copie de développement. Aucune modification locale ne doit être appliquée
automatiquement à la tour Windows, au Raspberry Pi ou au tunnel Cloudflare.

## Installation

1. Cloner le dépôt dans un dossier de travail.
2. Ne jamais importer de fichier `.env`, credential Cloudflare ou clé SSH privée.
3. Utiliser `raspberry/config/remote-wake.env.example` avec des valeurs factices.
4. Lire `AGENTS.md` avant toute intervention assistée par Codex.

## Branches et commits

- Créer une branche courte depuis `main`.
- Utiliser des commits ciblés et explicites.
- Documenter toute évolution du protocole dans `docs/ARCHITECTURE.md`.
- Ajouter des tests qui n'ont besoin ni du PC réel ni du Raspberry réel.

## Validation minimale

- syntaxe Python valide ;
- syntaxe PowerShell valide ;
- aucun secret ou état runtime versionné ;
- aucune action d'alimentation exécutée pendant les tests ;
- documentation mise à jour lorsque l'architecture change.

## Déploiement

Un déploiement est une opération distincte du développement. Il nécessite une demande
explicite, une sauvegarde datée, une validation locale et une procédure de retour arrière.

