# Changelog

Les changements notables de PC Control seront documentés dans ce fichier.

## Unreleased

### Added

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
