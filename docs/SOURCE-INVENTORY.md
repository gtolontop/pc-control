# Inventaire des sources récupérées

## Raspberry Pi

- Source active : `/opt/remote-wake`
- Copie locale : `raspberry/app`
- Code principal : `server.py` et `portal_ui.py`
- Les sauvegardes historiques présentes dans le dossier actif ont été conservées.
- Services copiés depuis `/etc/systemd/system`.
- Watchdog copié depuis `/usr/local/sbin/pc-wake-watchdog`.
- Aucun fichier `/etc/remote-wake.env`, credential Cloudflare ou clé privée n'a été copié.

## Windows

- Source active : `C:\PCMode`
- Copie locale : `windows-agent`
- Les logs, états runtime, outils binaires et sauvegardes datées ont été exclus.
- Les scripts actifs, configurations JSON et documentations ont été conservés.

## Lanceurs

- Source active : `C:\Users\teamr\Desktop\PCMode`
- Copie locale : `desktop-launchers`

## Tunnel identifié

La route active est `wake.your-script.com` vers `http://127.0.0.1:8789` sur le Raspberry.
La configuration fournie dans le projet est volontairement réduite et ne contient aucun secret.

