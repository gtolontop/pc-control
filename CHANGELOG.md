# Changelog

Les changements notables de PC Control seront documentés dans ce fichier.

## Unreleased

### Performance

- canal direct TCP sur le LAN (connect-back de l'agent vers le Raspberry) : latence
  d'entrée ~8 ms et flux d'écran ~26 img/s, contre ~0,5-2 s auparavant ;
- daemon de capture permanent avec déduplication d'images et curseur séparé dessiné
  côté client : bande passante quasi nulle sur un écran statique ;
- reconnexion automatique du canal, repli SSH ponctuel tant qu'il n'est pas établi.

### Added

- interface v11 refondue : plus fluide, micro-animations, streaming d'écran continu ;
- écran distant : glisser-déposer (drag), molette au doigt, plein écran, clavier live,
  « coller » du presse-papiers du téléphone vers le PC ;
- fichiers : transferts par morceaux sans limite de taille avec barre de progression,
  aperçu image, tri, renommage ;
- transferts de fichiers volumineux via FsDownloadChunk / FsWriteChunk.

- refonte complète de l'interface PWA : sobre, mobile-first, barre d'onglets
  (Accueil, Écran, Fichiers, Système, Terminal) ;
- pilotage direct de l'écran depuis le téléphone : capture en direct, clic (tap),
  clic droit (appui long), double-clic, clavier, défilement, volume, touches média ;
- explorateur de fichiers distant : navigation, aperçu texte, téléchargement,
  envoi, création de dossier, suppression, ouverture sur le PC ;
- terminal distant PowerShell / cmd et gestion des processus (liste, arrêt) ;
- lanceur d'applications et vue des disques ;
- agent de session Windows (`pccontrol-agent.ps1`) + capture isolée
  (`pccontrol-capture.ps1`) + pont enrichi (`pccontrol-bridge.ps1`) ;
- canal d'action riche `/api/action` (liste blanche stricte, payload sur stdin SSH) ;
- dépôt de développement unifié et snapshots Raspberry / Windows / lanceurs ;
- documentation d'architecture, contrainte antivirus et règles de sécurité.
