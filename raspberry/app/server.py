#!/usr/bin/env python3
"""GTOL PC Control — portail PWA de télécommande de la tour Windows.

Le service écoute en local sur le Raspberry Pi ; Cloudflare Tunnel l'expose sur
https://wake.your-script.com. Aucune route ne permet d'exécuter une commande
arbitraire : /api/control n'accepte que les actions listées dans CONTROL_ACTIONS,
et le pont Windows revérifie cette liste de son côté.
"""

import base64
import hashlib
import hmac
import json
import os
import re
import socket
import sqlite3
import struct
import subprocess
import threading
import time
import zlib
from collections import defaultdict, deque
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit


# --------------------------------------------------------------------------- #
# Configuration
# --------------------------------------------------------------------------- #

HOST = "127.0.0.1"
PORT = int(os.environ.get("REMOTE_WAKE_PORT", "8789"))
TOKEN = os.environ["REMOTE_WAKE_TOKEN"]
PC_MAC = os.environ["REMOTE_WAKE_MAC"]
PC_IP = os.environ.get("REMOTE_WAKE_IP", "192.168.1.100")
PC_HOST = os.environ.get("REMOTE_WAKE_HOST", "gtol.local")
PC_USER = os.environ.get("REMOTE_WAKE_USER", "teamr")
BROADCAST = os.environ.get("REMOTE_WAKE_BROADCAST", "192.168.1.255")
INTERFACE = os.environ.get("REMOTE_WAKE_INTERFACE", "wlan0")
SSH_KEY = os.environ.get("REMOTE_WAKE_SSH_KEY", "/etc/remote-wake/id_ed25519")
SSH_KNOWN_HOSTS = "/var/lib/remote-wake/known_hosts"
MANUAL_OFF_FILE = "/var/lib/remote-wake/manual-off"
TELEMETRY_DB = "/var/lib/remote-wake/telemetry.db"

# Permet plus tard de publier un vrai APK (Trusted Web Activity) sans toucher au code :
# il suffit de déposer le fichier de vérification Android à cet emplacement.
ASSETLINKS_FILE = os.environ.get(
    "REMOTE_WAKE_ASSETLINKS", "/etc/remote-wake/assetlinks.json"
)

RATE_WINDOW_SECONDS = 60
RATE_MAX_REQUESTS = 30
# Le pilotage direct (souris, écran, clavier) génère beaucoup plus de requêtes
# légitimes qu'une simple lecture d'état : on lui accorde un quota bien plus large.
RATE_MAX_CONTROL = 600
# Le flux d'écran interroge souvent (jusqu'à ~15/s) ; quota dédié généreux.
RATE_MAX_SCREEN = 1800
ATTEMPTS = defaultdict(deque)
CONTROL_ATTEMPTS = defaultdict(deque)
SCREEN_ATTEMPTS = defaultdict(deque)
STATUS_CONDITION = threading.Condition()
LATEST_STATUS = None
LATEST_STATUS_VERSION = 0
STATUS_SUBSCRIBERS = 0
LAST_DB_CLEANUP = 0

# Nom public envoyé par le portail -> action acceptée par le pont Windows.
CONTROL_ACTIONS = {
    "status": "Status",
    "share-parsec": "ShareParsec",
    "repair-parsec": "RepairParsec",
    "launch-codex": "LaunchCodex",
    "repair-fans": "RepairFans",
    "normal": "Normal",
    "night": "Night",
    "hibernate": "Hibernate",
    "reboot": "Reboot",
}

# Actions riches relayées telles quelles au pont Windows via le canal `Invoke`.
# Le pont applique la liste blanche réelle ; on la reproduit ici en garde-fou pour
# rejeter au plus tôt tout nom d'action non prévu.
RICH_ACTIONS = {
    # Bureau interactif (agent de session).
    "Screenshot", "ScreenInfo", "StreamStart", "StreamStop", "Click", "MoveMouse", "Drag",
    "Scroll", "TypeText", "SendKey", "Volume", "Media", "Lock", "DisplaysOff", "DisplaysOn",
    "GetClipboard", "SetClipboard", "WindowList", "FocusWindow", "CloseWindow", "Launch",
    "OpenPath", "OpenUrl", "Notify", "SessionInfo", "LogOff",
    # Système (pont SSH).
    "Frame", "FsList", "FsRead", "FsWrite", "FsDelete", "FsMkdir", "FsRename", "FsDownload",
    "FsStat", "FsDownloadChunk", "FsWriteChunk", "Drives", "Processes", "KillProcess",
    "Exec", "BridgeStatus",
}

# Lectures pures : ne polluent pas le journal d'audit.
READ_ONLY_ACTIONS = {
    "Screenshot", "ScreenInfo", "SessionInfo", "BridgeStatus", "WindowList", "Frame",
    "FsList", "FsRead", "FsStat", "FsDownload", "FsDownloadChunk", "Drives", "Processes",
    "GetClipboard", "MoveMouse", "StreamStart", "StreamStop",
}

# Actions longues : terminal, transferts de fichiers. Délai réseau plus large.
RICH_TIMEOUTS = {
    "Screenshot": 45,
    "Exec": 130,
    "FsDownload": 60,
    "FsDownloadChunk": 45,
    "FsWriteChunk": 45,
    "FsWrite": 60,
}


# --------------------------------------------------------------------------- #
# Interface : une seule page, monochrome, installable
# --------------------------------------------------------------------------- #

STYLE = """
*, *::before, *::after { box-sizing: border-box }

:root {
  --bg: #000;
  --fg: #fff;
  --dim: #7c7c7c;
  --line: #1e1e1e;
  --edge: #333;
  --press: #cdcdcd;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, system-ui, sans-serif;
  -webkit-tap-highlight-color: transparent;
}

html { background: var(--bg) }

body {
  margin: 0;
  min-height: 100dvh;
  padding: max(22px, env(safe-area-inset-top)) 16px calc(24px + env(safe-area-inset-bottom));
  background: var(--bg);
  color: var(--fg);
  font-size: 15px;
  line-height: 1.4;
  -webkit-font-smoothing: antialiased;
}

main { width: 100%; max-width: 430px; margin: 0 auto }
[hidden] { display: none !important }

h1 { margin: 0; font-size: 15px; font-weight: 600; letter-spacing: .16em; text-transform: uppercase }

.head {
  display: flex; align-items: baseline; justify-content: space-between; gap: 12px;
  padding-bottom: 13px; border-bottom: 1px solid var(--line);
}
.head span { font-size: 11px; letter-spacing: .12em; text-transform: uppercase; color: var(--dim) }

/* Ligne d'état permanente : premier repère de lecture. */
.msg {
  display: flex; align-items: flex-start; gap: 9px;
  margin: 16px 0 20px; min-height: 34px;
  font-size: 13px; color: var(--fg);
}
.dot {
  flex: none; width: 7px; height: 7px; margin-top: 6px;
  border: 1px solid var(--dim); border-radius: 50%;
}
.dot.on { background: var(--fg); border-color: var(--fg) }
.dot.off { background: transparent; border-color: var(--dim) }
.dot.busy { background: var(--dim); border-color: var(--dim); animation: pulse 1s infinite ease-in-out }
.dot.err { background: var(--fg); border-color: var(--fg); border-radius: 0 }
@keyframes pulse { 50% { opacity: .25 } }
.msg.err span:last-child { text-decoration: underline; text-underline-offset: 3px }

/* Actions : mêmes rectangles pour tout, inversion au doigt. */
.act {
  display: flex; align-items: center; justify-content: space-between;
  width: 100%; margin-top: 8px; padding: 0 14px; height: 50px;
  border: 1px solid var(--edge); border-radius: 4px;
  background: transparent; color: var(--fg);
  font: inherit; font-size: 13px; font-weight: 500; letter-spacing: .07em; text-transform: uppercase;
  text-align: left; text-decoration: none; cursor: pointer;
  transition: background .12s, color .12s, border-color .12s, opacity .12s;
}
.act:active { background: var(--fg); color: var(--bg); border-color: var(--fg) }
.act:disabled { opacity: .35; cursor: default }
.act.primary { background: var(--fg); color: var(--bg); border-color: var(--fg); font-weight: 700 }
.act.primary:active { background: var(--press); border-color: var(--press) }
.act.armed { background: var(--fg); color: var(--bg); border-color: var(--fg) }

.group { margin-top: 24px }
.pair { display: grid; grid-template-columns: 1fr 1fr; gap: 8px }
.pair .act { margin-top: 0 }

/* État de la tour : lignes étiquette / valeur. */
.rows { margin: 0; padding: 0; border-top: 1px solid var(--line) }
.rows div {
  display: flex; align-items: baseline; justify-content: space-between; gap: 14px;
  padding: 11px 1px; border-bottom: 1px solid var(--line);
}
.rows dt { font-size: 10px; letter-spacing: .14em; text-transform: uppercase; color: var(--dim) }
.rows dd {
  margin: 0; font-size: 13px; text-align: right;
  font-variant-numeric: tabular-nums;
}
.rows dd.weak { color: var(--dim) }

label { display: block; margin: 0 0 9px; font-size: 10px; letter-spacing: .2em; text-transform: uppercase; color: var(--dim) }
input {
  width: 100%; height: 48px; margin-bottom: 10px; padding: 0 14px;
  border: 1px solid var(--edge); border-radius: 4px;
  background: var(--bg); color: var(--fg);
  font: inherit; letter-spacing: .08em; outline: none;
}
input:focus { border-color: var(--fg) }

.foot { margin: 30px 0 0; padding-top: 16px; border-top: 1px solid var(--line) }
.ghost {
  display: block; padding: 0; border: 0; background: none; color: var(--dim);
  font: inherit; font-size: 11px; letter-spacing: .1em; text-transform: uppercase;
  text-decoration: underline; text-underline-offset: 3px; cursor: pointer;
}
.ghost:active { color: var(--fg) }
"""

SCRIPT = """
(() => {
  "use strict";

  const $ = (selector) => document.querySelector(selector);
  const STORE = "pcControlKey";
  const POLL_MS = 25000;         // rafraîchissement de fond
  const WAKE_POLL_MS = 6000;     // surveillance après un Wake-on-LAN
  const WAKE_WINDOW_MS = 150000;

  const gate = $("#gate");
  const app = $("#app");
  const keyField = $("#key");
  const dot = $("#dot");
  const msg = $("#msg");
  const msgText = $("#msgText");
  const rows = $("#rows");
  const hostName = $("#host");

  let key = localStorage.getItem(STORE) || "";
  let busy = false;
  let wakeUntil = 0;
  let armed = null;

  // La clé est retenue définitivement sur ce téléphone : jamais redemandée, même après
  // fermeture de l'application ou redémarrage. On accepte aussi un lien d'accès de la
  // forme .../#k=LA_CLE ; le fragment n'est jamais envoyé au serveur et il est effacé
  // de l'historique dès qu'il est lu.
  const linkKey = new URLSearchParams(location.hash.slice(1)).get("k");
  if (linkKey && linkKey.trim()) {
    key = linkKey.trim();
    localStorage.setItem(STORE, key);
    history.replaceState(null, "", location.pathname + location.search);
  }
  // Empêche Chrome d'effacer la clé quand il fait de la place.
  if (navigator.storage && navigator.storage.persist) {
    navigator.storage.persist().catch(() => {});
  }

  // Chaque ligne d'état : étiquette, valeur lue dans /api/status, valeur grisée si à surveiller.
  const READINGS = [
    ["Tour", (d) => d.online ? (d.control_ready ? "En ligne" : "Pont HS") : "Éteinte",
      (d) => !d.online],
    ["Parsec", (d) => !d.pc ? "—"
      : d.pc.parsec_ready ? "Hôte prêt"
      : !d.pc.parsec_host ? "Hébergement off"
      : "À partager", (d) => !d.pc || !d.pc.parsec_ready],
    ["Codex", (d) => !d.pc ? "—" : d.pc.codex ? "Ouvert" : "Fermé", (d) => !d.pc || !d.pc.codex],
    ["Ventilos", (d) => !d.pc ? "—" : d.pc.fan_control ? "FanControl" : "BIOS seul",
      (d) => !d.pc || !d.pc.fan_control],
    ["Mode", (d) => !d.pc ? "—" : d.pc.mode === "night" ? "Nuit" : "Normal"],
    ["Depuis", (d) => d.pc ? duration(d.pc.uptime_minutes) : "—"],
    ["RAM libre", (d) => d.pc ? d.pc.memory_free_gb + " Go" : "—"]
  ];

  function duration(minutes) {
    if (typeof minutes !== "number") return "—";
    const h = Math.floor(minutes / 60);
    const m = minutes % 60;
    return h ? h + " h " + String(m).padStart(2, "0") : m + " min";
  }

  function tap() {
    if (navigator.vibrate) navigator.vibrate(8);
  }

  function setMessage(text, tone) {
    dot.className = "dot " + (tone === "err" ? "err" : tone || "");
    msg.className = "msg" + (tone === "err" ? " err" : "");
    msgText.textContent = text;
  }

  function setBusy(value) {
    busy = value;
    app.querySelectorAll("button").forEach((button) => { button.disabled = value; });
  }

  function disarm() {
    if (!armed) return;
    armed.button.classList.remove("armed");
    armed.button.textContent = armed.label;
    clearTimeout(armed.timer);
    armed = null;
  }

  function render(data) {
    if (data.pc && data.pc.computer) hostName.textContent = data.pc.computer;
    rows.textContent = "";
    for (const [label, read, weak] of READINGS) {
      const line = document.createElement("div");
      const dt = document.createElement("dt");
      const dd = document.createElement("dd");
      dt.textContent = label;
      dd.textContent = read(data);
      if (weak && weak(data)) dd.className = "weak";
      line.append(dt, dd);
      rows.append(line);
    }
  }

  async function api(path, method, payload) {
    const options = { method: method || "GET", headers: { Authorization: "Bearer " + key } };
    if (payload) {
      options.headers["Content-Type"] = "application/json";
      options.body = JSON.stringify(payload);
    }
    let response;
    try {
      response = await fetch(path, options);
    } catch (error) {
      throw new Error("Pas de réseau.");
    }
    const data = await response.json().catch(() => ({}));
    if (response.status === 401) {
      const failure = new Error("Clé refusée.");
      failure.unauthorized = true;
      throw failure;
    }
    if (!response.ok) throw new Error(data.error || "Action impossible.");
    return data;
  }

  function lock(reason) {
    localStorage.removeItem(STORE);
    key = "";
    app.hidden = true;
    gate.hidden = false;
    keyField.value = "";
    if (reason) keyField.placeholder = reason;
  }

  // Un /api/status coûte un aller-retour SSH : silent = ne pas clignoter à chaque tick.
  async function refresh(silent) {
    if (busy) return;
    if (!silent) { setBusy(true); setMessage("Lecture…", "busy"); }
    try {
      const data = await api("/api/status");
      render(data);
      setMessage(data.message || "À jour.", data.online ? "on" : "off");
    } catch (error) {
      if (error.unauthorized) return lock("Clé refusée");
      if (!silent) setMessage(error.message, "err");
    } finally {
      if (!silent) setBusy(false);
    }
  }

  async function control(action, label) {
    setBusy(true);
    setMessage(label + "…", "busy");
    try {
      const data = await api("/api/control", "POST", { action });
      setMessage(data.message || data.error || "Terminé.", data.ok === false ? "err" : "on");
      setBusy(false);
      await refresh(true);
    } catch (error) {
      setBusy(false);
      if (error.unauthorized) return lock("Clé refusée");
      setMessage(error.message, "err");
    }
  }

  async function wake() {
    setBusy(true);
    setMessage("Allumage…", "busy");
    try {
      const data = await api("/api/wake", "POST");
      setMessage(data.message || "Signal envoyé.", data.online ? "on" : "busy");
      wakeUntil = Date.now() + WAKE_WINDOW_MS;
      setBusy(false);
      watchWake();
    } catch (error) {
      setBusy(false);
      if (error.unauthorized) return lock("Clé refusée");
      setMessage(error.message, "err");
    }
  }

  // Après un réveil, on interroge la tour jusqu'à ce qu'elle réponde.
  async function watchWake() {
    if (Date.now() > wakeUntil || busy) return;
    try {
      const data = await api("/api/status");
      render(data);
      if (data.online) {
        wakeUntil = 0;
        setMessage(data.message || "Tour allumée.", "on");
        return;
      }
      setMessage("Démarrage…", "busy");
    } catch (error) {
      if (error.unauthorized) return lock("Clé refusée");
    }
    setTimeout(watchWake, WAKE_POLL_MS);
  }

  function unlock(value) {
    key = value.trim();
    if (!key) return;
    localStorage.setItem(STORE, key);
    gate.hidden = true;
    app.hidden = false;
    refresh(false).then(runShortcut);
  }

  // Raccourcis de l'icône Android : /?do=wake, /?do=share-parsec, /?do=launch-codex
  function runShortcut() {
    const wanted = new URLSearchParams(location.search).get("do");
    if (!wanted) return;
    history.replaceState(null, "", "/");
    if (wanted === "wake") return wake();
    const button = app.querySelector('[data-action="' + wanted + '"]');
    if (button && !button.dataset.confirm) button.click();
  }

  $("#unlock").addEventListener("submit", (event) => {
    event.preventDefault();
    unlock(keyField.value);
  });
  $("#wake").addEventListener("click", () => { tap(); disarm(); wake(); });
  $("#refresh").addEventListener("click", () => { tap(); disarm(); refresh(false); });
  $("#forget").addEventListener("click", () => { tap(); lock("Clé"); });

  app.querySelectorAll("[data-action]").forEach((button) => {
    const label = button.textContent.trim();
    button.addEventListener("click", () => {
      tap();

      // Actions lourdes : deux appuis, sans boîte de dialogue.
      if (button.dataset.confirm && (!armed || armed.button !== button)) {
        disarm();
        button.classList.add("armed");
        button.textContent = "Confirmer";
        armed = { button, label, timer: setTimeout(disarm, 5000) };
        return;
      }
      disarm();
      control(button.dataset.action, label);
    });
  });

  document.addEventListener("visibilitychange", () => {
    if (!document.hidden && key) refresh(true);
  });
  setInterval(() => { if (!document.hidden && key && !wakeUntil) refresh(true); }, POLL_MS);

  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("/sw.js").catch(() => {});
  }

  if (key) {
    gate.hidden = true;
    app.hidden = false;
    refresh(false).then(runShortcut);
  }
})();
"""

BODY = """
<main id="gate">
  <h1>PC Control</h1>
  <form id="unlock" class="group">
    <label for="key">Clé</label>
    <input id="key" type="password" autocomplete="current-password" spellcheck="false"
           autocapitalize="off" placeholder="Une seule fois">
    <button class="act primary" type="submit">Entrer</button>
  </form>
</main>

<main id="app" hidden>
  <div class="head"><h1>PC Control</h1><span id="host">GTOL</span></div>

  <p id="msg" class="msg"><span class="dot busy" id="dot"></span><span id="msgText">…</span></p>

  <div class="pair">
    <button class="act primary" id="wake">Allumer</button>
    <button class="act" id="refresh">Vérifier</button>
  </div>

  <dl class="rows group" id="rows"></dl>

  <div class="group">
    <button class="act" data-action="share-parsec">Partager le PC</button>
    <button class="act" data-action="launch-codex">Lancer Codex</button>
    <a class="act" href="https://parsec.app/" target="_blank" rel="noopener noreferrer">Ouvrir Parsec ↗</a>
  </div>

  <div class="group pair">
    <button class="act" data-action="normal">Normal</button>
    <button class="act" data-action="night">Nuit</button>
  </div>

  <div class="group">
    <button class="act" data-action="repair-parsec">Réparer Parsec</button>
    <button class="act" data-action="repair-fans">Ventilateurs</button>
    <button class="act" data-action="hibernate" data-confirm="1">Éteindre (réveil WOL)</button>
    <button class="act" data-action="reboot" data-confirm="1">Redémarrer</button>
  </div>

  <div class="foot"><button class="ghost" id="forget">Oublier la clé</button></div>
</main>
"""

PAGE = """<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#000000">
<meta name="color-scheme" content="dark">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="PC Control">
<link rel="manifest" href="/manifest.webmanifest">
<link rel="icon" type="image/svg+xml" href="/icon.svg">
<link rel="apple-touch-icon" href="/icon-192.png">
<title>PC Control</title>
<style>__STYLE__</style>
</head>
<body>
<noscript><main><h1>PC Control</h1><p class="group">JavaScript requis.</p></main></noscript>
__BODY__
<script>__SCRIPT__</script>
</body>
</html>
""".replace("__STYLE__", STYLE).replace("__BODY__", BODY).replace("__SCRIPT__", SCRIPT)


MANIFEST = {
    "name": "GTOL PC Control",
    "short_name": "PC Control",
    "description": "Réveil, partage et dépannage distant de la tour GTOL",
    "id": "/",
    "start_url": "/",
    "scope": "/",
    "display": "standalone",
    "display_override": ["standalone", "minimal-ui"],
    "orientation": "portrait",
    "background_color": "#000000",
    "theme_color": "#000000",
    "categories": ["utilities"],
    "icons": [
        {"src": "/icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any"},
        {"src": "/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any"},
        {"src": "/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable"},
    ],
    "shortcuts": [
        {"name": "Allumer la tour", "short_name": "Allumer", "url": "/?do=wake"},
        {"name": "Partager le PC", "short_name": "Partager", "url": "/?do=share-parsec"},
        {"name": "Lancer Codex", "short_name": "Codex", "url": "/?do=launch-codex"},
    ],
}

ICON = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
<rect width="512" height="512" fill="#000000"/>
<path d="M256 150v112" fill="none" stroke="#ffffff" stroke-width="30" stroke-linecap="round"/>
<path d="M186 196a124 124 0 1 0 140 0" fill="none" stroke="#ffffff" stroke-width="30" stroke-linecap="round"/>
</svg>"""

SERVICE_WORKER = """const CACHE = "pc-control-v3";
const SHELL = ["/", "/manifest.webmanifest", "/icon.svg", "/icon-192.png", "/icon-512.png"];
self.addEventListener("install", (event) => {
  self.skipWaiting();
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)));
});
self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});
self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET" || new URL(request.url).pathname.startsWith("/api/")) return;
  event.respondWith(
    fetch(request)
      .then((response) => {
        const copy = response.clone();
        caches.open(CACHE).then((cache) => cache.put(request, copy)).catch(() => {});
        return response;
      })
      .catch(() => caches.match(request).then((hit) => hit || caches.match("/")))
  );
});
"""


def make_png_icon(size):
    """Icône monochrome (fond noir, symbole d'alimentation blanc), sans dépendance."""
    pixels = bytearray()
    center = (size - 1) / 2
    for y in range(size):
        pixels.append(0)  # filtre de ligne PNG
        for x in range(size):
            nx = (x - center) / size
            ny = (y - center) / size
            distance = (nx * nx + ny * ny) ** 0.5
            ring = 0.205 < distance < 0.250
            opening = ny < -0.10 and abs(nx) < 0.105
            stem = abs(nx) < 0.023 and -0.255 < ny < 0.015
            white = (ring and not opening) or stem
            pixels.extend((255, 255, 255, 255) if white else (0, 0, 0, 255))

    def chunk(kind, data):
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(pixels), 9))
        + chunk(b"IEND", b"")
    )


HTML_TYPE = "text/html; charset=utf-8"
JSON_TYPE = "application/json; charset=utf-8"
DAY = "public, max-age=86400"

# L'interface est isolée du backend afin de pouvoir évoluer sans toucher aux
# garde-fous Wake-on-LAN et SSH.
from portal_ui import MANIFEST, PAGE, SERVICE_WORKER

# chemin -> (corps, type, cache)
STATIC_ROUTES = {
    "/": (PAGE.encode(), HTML_TYPE, "no-store, no-cache, must-revalidate"),
    "/manifest.webmanifest": (
        json.dumps(MANIFEST, ensure_ascii=False).encode(),
        "application/manifest+json; charset=utf-8",
        "public, max-age=3600",
    ),
    "/icon.svg": (ICON.encode(), "image/svg+xml; charset=utf-8", DAY),
    "/icon-192.png": (make_png_icon(192), "image/png", DAY),
    "/icon-512.png": (make_png_icon(512), "image/png", DAY),
    "/sw.js": (SERVICE_WORKER.encode(), "application/javascript; charset=utf-8", "no-cache"),
}


# --------------------------------------------------------------------------- #
# Accès, réseau, pont Windows
# --------------------------------------------------------------------------- #


def authorized(header):
    prefix = "Bearer "
    return bool(
        header
        and header.startswith(prefix)
        and hmac.compare_digest(header[len(prefix):], TOKEN)
    )


def rate_limited(address):
    now = time.monotonic()
    entries = ATTEMPTS[address]
    while entries and now - entries[0] > RATE_WINDOW_SECONDS:
        entries.popleft()
    if len(entries) >= RATE_MAX_REQUESTS:
        return True
    entries.append(now)
    return False


def rate_limited_control(address):
    now = time.monotonic()
    entries = CONTROL_ATTEMPTS[address]
    while entries and now - entries[0] > RATE_WINDOW_SECONDS:
        entries.popleft()
    if len(entries) >= RATE_MAX_CONTROL:
        return True
    entries.append(now)
    return False


def rate_limited_screen(address):
    now = time.monotonic()
    entries = SCREEN_ATTEMPTS[address]
    while entries and now - entries[0] > RATE_WINDOW_SECONDS:
        entries.popleft()
    if len(entries) >= RATE_MAX_SCREEN:
        return True
    entries.append(now)
    return False


def resolve_pc_ip():
    try:
        return socket.gethostbyname(PC_HOST)
    except socket.gaierror:
        return PC_IP


def is_online():
    target = resolve_pc_ip()
    arp = subprocess.run(
        ["arping", "-c", "1", "-w", "1", "-I", INTERFACE, target],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if arp.returncode == 0:
        return True
    return (
        subprocess.run(
            ["ping", "-c", "1", "-W", "1", target],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode
        == 0
    )


def set_manual_off(enabled):
    """Suspend le watchdog après une extinction volontaire, jusqu'au prochain Wake."""
    if enabled:
        temporary = MANUAL_OFF_FILE + ".tmp"
        with open(temporary, "w", encoding="ascii") as handle:
            handle.write(str(int(time.time())))
        os.replace(temporary, MANUAL_OFF_FILE)
        return
    try:
        os.unlink(MANUAL_OFF_FILE)
    except FileNotFoundError:
        pass


def wake():
    raw = bytes.fromhex(PC_MAC.replace(":", "").replace("-", ""))
    packet = b"\xff" * 6 + raw * 16
    broadcasts = {BROADCAST, "255.255.255.255"}
    addresses = subprocess.run(
        ["ip", "-4", "addr", "show", "dev", INTERFACE],
        capture_output=True,
        text=True,
        check=False,
    ).stdout
    match = re.search(r"\bbrd\s+(\d+\.\d+\.\d+\.\d+)", addresses)
    if match:
        broadcasts.add(match.group(1))
    targets = broadcasts | {resolve_pc_ip()}
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        for target in targets:
            for port in (9, 7):
                for _ in range(3):
                    sock.sendto(packet, (target, port))
                    time.sleep(0.08)


def decode_windows(raw):
    """Windows renvoie parfois du CP1252 sur SSH : ne jamais échouer sur un octet isolé."""
    for encoding in ("utf-8", "cp1252"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", "replace")


def ssh_base(connect_timeout=6):
    """Options SSH communes au pont Windows.

    Pas de multiplexage ControlMaster : sur Win32-OpenSSH, des exécutions
    concurrentes partageant un même maître voient leurs sorties se croiser. La
    vitesse vient du canal TCP persistant (TunnelChannel) ; les commandes SSH
    ponctuelles restent, elles, en connexion dédiée et fiable.
    """
    return [
        "/usr/bin/ssh",
        "-i",
        SSH_KEY,
        "-o",
        "BatchMode=yes",
        "-o",
        f"ConnectTimeout={connect_timeout}",
        "-o",
        "StrictHostKeyChecking=accept-new",
        "-o",
        f"UserKnownHostsFile={SSH_KNOWN_HOSTS}",
    ]


def last_json(output):
    """Les scripts Windows peuvent journaliser : on garde le dernier objet JSON."""
    for line in reversed(output.splitlines()):
        line = line.strip()
        if not line:
            continue
        try:
            parsed = json.loads(line)
            if isinstance(parsed, dict):
                return parsed
        except json.JSONDecodeError:
            continue
    return None


def pc_control(action):
    """Exécute un verbe historique du pont Windows par SSH (multiplexé)."""
    command = ssh_base() + [f"{PC_USER}@{PC_HOST}", action]
    try:
        result = subprocess.run(command, capture_output=True, timeout=90, check=False)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError("La tour ne répond pas à temps.") from error

    output = decode_windows(result.stdout).strip()
    errors = decode_windows(result.stderr).strip()
    parsed = last_json(output)

    if result.returncode != 0:
        detail = ""
        if isinstance(parsed, dict) and parsed.get("error"):
            detail = parsed["error"]
        elif errors:
            detail = errors.splitlines()[-1]
        raise RuntimeError(detail or "Le pont Windows n'est pas joignable.")
    if not isinstance(parsed, dict):
        return {"ok": True, "message": output or "Action terminée."}
    return parsed


def pc_invoke(action, args=None, timeout=60):
    """Envoie une action riche { action, args } au pont via le canal `Invoke` one-shot.

    Repli lorsque le canal persistant est indisponible. Le payload JSON transite par
    l'entrée standard SSH ; la liste blanche réelle est appliquée côté Windows.
    """
    payload = json.dumps({"action": action, "args": args or {}}, ensure_ascii=False)
    command = ssh_base() + [f"{PC_USER}@{PC_HOST}", "Invoke"]
    try:
        result = subprocess.run(
            command,
            input=payload.encode("utf-8"),
            capture_output=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise RuntimeError("La tour ne répond pas à temps.") from error

    output = decode_windows(result.stdout).strip()
    errors = decode_windows(result.stderr).strip()
    parsed = last_json(output)

    if result.returncode != 0 and not isinstance(parsed, dict):
        detail = errors.splitlines()[-1] if errors else ""
        raise RuntimeError(detail or "Le pont Windows n'est pas joignable.")
    if not isinstance(parsed, dict):
        raise RuntimeError("Réponse illisible du pont Windows.")
    return parsed


AGENT_LISTEN_PORT = int(os.environ.get("REMOTE_WAKE_AGENT_PORT", "8790"))

# Actions servies par l'agent de session via le canal direct (bureau + trames).
# Les actions système (fichiers, processus, terminal) passent par le canal `Run`.
CHANNEL_ACTIONS = {
    "Frame", "Screenshot", "ScreenInfo", "StreamStart", "StreamStop", "Click", "MoveMouse",
    "Drag", "Scroll", "TypeText", "SendKey", "Volume", "Media", "Lock", "DisplaysOff",
    "DisplaysOn", "GetClipboard", "SetClipboard", "WindowList", "FocusWindow", "CloseWindow",
    "Launch", "OpenPath", "OpenUrl", "Notify", "SessionInfo", "LogOff",
}


class LanAgentChannel:
    """Canal TCP direct sur le réseau local vers l'agent de session.

    Toute forme de tunnel SSH vers l'agent s'est révélée soit cassée soit lente sur
    le Win32-OpenSSH de la tour (multiplexage qui croise les sorties, stdin partiel,
    forward ~2 s). On inverse donc le sens : le Raspberry écoute un port sur le LAN,
    et demande à l'agent (via une commande `Run` ponctuelle) de s'y connecter en TCP
    direct. Une fois la connexion établie, toutes les actions bureau et les trames
    passent par ce socket réutilisé, sans SSH ni démarrage de processus : latence
    ~réseau local (quelques millisecondes).
    """

    def __init__(self):
        self.lock = threading.Lock()
        self.conn = None
        self.reader = None
        self.seq = 0
        # Jeton STABLE (dérivé de la clé Bearer) : un redémarrage du service ne le
        # change pas, donc l'agent déjà connecté reste valide et se reconnecte seul.
        # La clé brute ne transite jamais sur le LAN (seulement ce condensé).
        self.token = hashlib.sha256((TOKEN + "|pc-control-lan").encode()).hexdigest()
        self.pi_ip = None
        try:
            threading.Thread(target=self._listen_loop, name="lan-agent-listen", daemon=True).start()
            threading.Thread(target=self._maintain_loop, name="lan-agent-maintain", daemon=True).start()
        except RuntimeError:
            pass

    def _lan_ip(self):
        try:
            probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            probe.connect((resolve_pc_ip(), 9))
            ip = probe.getsockname()[0]
            probe.close()
            return ip
        except OSError:
            return PC_IP

    def _listen_loop(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            server.bind(("0.0.0.0", AGENT_LISTEN_PORT))
            server.listen(1)
        except OSError as error:
            print(f"lan-agent: bind impossible: {error}", flush=True)
            return
        while True:
            try:
                client, _ = server.accept()
                client.settimeout(8)
                reader = client.makefile("rb")
                hello = reader.readline()
                if hello.decode("utf-8", "replace").strip() != self.token:
                    client.close()
                    continue
                client.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                client.settimeout(20)
                with self.lock:
                    self._drop()
                    self.conn = client
                    self.reader = reader
                print("lan-agent: agent connecté", flush=True)
            except OSError:
                time.sleep(0.5)

    def _maintain_loop(self):
        # Tant qu'aucun agent n'est connecté, on lui demande (via SSH ponctuel) de se
        # connecter en retour. Uniquement quand la tour est en ligne.
        while True:
            if self.conn is None and (LATEST_STATUS is None or LATEST_STATUS.get("online")):
                if self.pi_ip is None:
                    self.pi_ip = self._lan_ip()
                try:
                    pc_action(
                        "ConnectBack",
                        {"host": self.pi_ip, "port": AGENT_LISTEN_PORT, "token": self.token},
                        timeout=20,
                    )
                except RuntimeError:
                    pass
            time.sleep(6)

    def _drop(self):
        for closable in (self.reader, self.conn):
            try:
                if closable:
                    closable.close()
            except OSError:
                pass
        self.reader = None
        self.conn = None

    def request(self, action, args=None, timeout=20):
        """Renvoie (header_dict, image_bytes). image_bytes est vide hors trame."""
        with self.lock:
            if self.conn is None:
                raise RuntimeError("Agent non connecté.")
            try:
                self.seq += 1
                self.conn.settimeout(timeout)
                payload = json.dumps(
                    {"id": self.seq, "action": action, "args": args or {}}, ensure_ascii=False
                ).encode("utf-8") + b"\n"
                self.conn.sendall(payload)
                header_line = self.reader.readline()
                if not header_line:
                    raise RuntimeError("Canal fermé.")
                header = json.loads(header_line.decode("utf-8", "replace"))
                length = int(header.get("img_len", 0) or 0)
                data = b""
                while len(data) < length:
                    chunk = self.reader.read(length - len(data))
                    if not chunk:
                        raise RuntimeError("Trame tronquée.")
                    data += chunk
                return header, data
            except (OSError, ValueError, RuntimeError) as error:
                self._drop()
                raise RuntimeError(str(error) or "Canal indisponible.")


CHANNEL = LanAgentChannel()


def pc_channel(action, args=None, timeout=20):
    return CHANNEL.request(action, args, timeout=timeout)


def pc_action(action, args=None, timeout=45):
    """Action riche via le canal rapide `Run` (multiplexé, payload en argument).

    Le multiplexage supprime la poignée de main SSH ; le payload JSON voyage encodé
    en base64 dans la ligne de commande (pas de stdin, donc compatible ControlMaster).
    Les payloads volumineux (transferts de fichiers) repassent par `Invoke` (stdin).
    Plusieurs appels concurrents ouvrent chacun un canal multiplexé : le client peut
    donc pipeliner les trames pour un débit supérieur.
    """
    payload = json.dumps({"action": action, "args": args or {}}, ensure_ascii=False)
    encoded = base64.b64encode(payload.encode("utf-8")).decode("ascii")
    if len(encoded) > 8000:
        return pc_invoke(action, args, timeout=timeout)

    command = ssh_base() + [f"{PC_USER}@{PC_HOST}", "Run " + encoded]
    try:
        result = subprocess.run(command, capture_output=True, timeout=timeout, check=False)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError("La tour ne répond pas à temps.") from error

    parsed = last_json(decode_windows(result.stdout).strip())
    if not isinstance(parsed, dict):
        errors = decode_windows(result.stderr).strip()
        detail = errors.splitlines()[-1] if errors else ""
        raise RuntimeError(detail or "Le pont Windows n'est pas joignable.")
    return parsed


def read_status():
    online = is_online()
    pc = None
    control_ready = False
    if online:
        try:
            pc = pc_control("Status")
            control_ready = bool(pc.get("ok"))
        except RuntimeError:
            pass

    if control_ready:
        message = "Tour prête."
        if pc and not pc.get("parsec_ready"):
            message = "Parsec hôte à remettre en ligne."
        elif pc and not pc.get("fan_control"):
            message = "FanControl arrêté."
    elif online:
        message = "Pont Windows injoignable."
    else:
        message = "Tour éteinte."

    try:
        with open("/proc/uptime", "r", encoding="ascii") as handle:
            gateway_uptime_minutes = int(float(handle.read().split()[0]) // 60)
    except (OSError, ValueError, IndexError):
        gateway_uptime_minutes = None

    return {
        "online": online,
        "control_ready": control_ready,
        "pc": pc,
        "message": message,
        "updated_at": int(time.time()),
        "gateway": {
            "uptime_minutes": gateway_uptime_minutes,
            "watchdog_suspended": os.path.exists(MANUAL_OFF_FILE),
        },
    }


# --------------------------------------------------------------------------- #
# Blackbox persistante : sept jours de télémétrie et audit partagé
# --------------------------------------------------------------------------- #


@contextmanager
def database():
    connection = sqlite3.connect(TELEMETRY_DB, timeout=5)
    connection.row_factory = sqlite3.Row
    try:
        with connection:
            yield connection
    finally:
        connection.close()


def init_database():
    with database() as connection:
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA synchronous=NORMAL")
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS telemetry (
                ts INTEGER PRIMARY KEY,
                online INTEGER NOT NULL,
                control_ready INTEGER NOT NULL,
                parsec_ready INTEGER NOT NULL,
                fan_control INTEGER NOT NULL,
                codex INTEGER NOT NULL,
                mode TEXT,
                cpu REAL,
                gpu REAL,
                temperature REAL,
                memory_used REAL,
                disk_used REAL,
                probe_ms INTEGER NOT NULL
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS audit (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts INTEGER NOT NULL,
                action TEXT NOT NULL,
                ok INTEGER NOT NULL,
                message TEXT NOT NULL,
                duration_ms INTEGER NOT NULL
            )
            """
        )
        connection.execute(
            "CREATE INDEX IF NOT EXISTS audit_ts_idx ON audit(ts DESC)"
        )


def record_telemetry(status, probe_ms):
    global LAST_DB_CLEANUP
    now = int(time.time())
    pc = status.get("pc") or {}
    try:
        with database() as connection:
            connection.execute(
                """
                INSERT OR REPLACE INTO telemetry (
                    ts, online, control_ready, parsec_ready, fan_control, codex,
                    mode, cpu, gpu, temperature, memory_used, disk_used, probe_ms
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    now,
                    bool(status.get("online")),
                    bool(status.get("control_ready")),
                    bool(pc.get("parsec_ready")),
                    bool(pc.get("fan_control")),
                    bool(pc.get("codex")),
                    pc.get("mode"),
                    pc.get("cpu_load_percent"),
                    pc.get("gpu_load_percent"),
                    pc.get("gpu_temperature_c"),
                    pc.get("memory_used_percent"),
                    pc.get("disk_used_percent"),
                    probe_ms,
                ),
            )
            if now - LAST_DB_CLEANUP >= 300:
                connection.execute(
                    "DELETE FROM telemetry WHERE ts < ?", (now - 7 * 86400,)
                )
                connection.execute(
                    "DELETE FROM audit WHERE ts < ?", (now - 30 * 86400,)
                )
                LAST_DB_CLEANUP = now
    except sqlite3.Error as error:
        print(f"blackbox telemetry: {error}", flush=True)


def record_audit(action, ok, message, duration_ms):
    try:
        with database() as connection:
            connection.execute(
                """
                INSERT INTO audit(ts, action, ok, message, duration_ms)
                VALUES (?, ?, ?, ?, ?)
                """,
                (
                    int(time.time()),
                    action[:40],
                    bool(ok),
                    str(message or "Terminé")[:300],
                    max(0, int(duration_ms)),
                ),
            )
    except sqlite3.Error as error:
        print(f"blackbox audit: {error}", flush=True)


def capture_status():
    started = time.monotonic()
    status = read_status()
    probe_ms = max(1, int((time.monotonic() - started) * 1000))
    status["probe_ms"] = probe_ms
    record_telemetry(status, probe_ms)
    return status


def read_history(minutes):
    seconds = minutes * 60
    bucket = max(1, seconds // 240)
    since = int(time.time()) - seconds
    with database() as connection:
        rows = connection.execute(
            """
            SELECT
                (ts / ?) * ? AS ts,
                ROUND(AVG(online) * 100, 1) AS availability,
                ROUND(AVG(control_ready) * 100, 1) AS bridge,
                ROUND(AVG(cpu), 1) AS cpu,
                ROUND(AVG(gpu), 1) AS gpu,
                ROUND(AVG(temperature), 1) AS temperature,
                ROUND(MAX(temperature), 1) AS temperature_peak,
                ROUND(AVG(memory_used), 1) AS memory_used,
                ROUND(AVG(disk_used), 1) AS disk_used,
                ROUND(AVG(probe_ms), 0) AS probe_ms
            FROM telemetry
            WHERE ts >= ?
            GROUP BY ts / ?
            ORDER BY ts
            """,
            (bucket, bucket, since, bucket),
        ).fetchall()
    return {
        "minutes": minutes,
        "bucket_seconds": bucket,
        "points": [dict(row) for row in rows],
    }


def read_summary(hours):
    since = int(time.time()) - hours * 3600
    with database() as connection:
        rows = connection.execute(
            """
            SELECT ts, online, control_ready, parsec_ready, fan_control, codex,
                   cpu, gpu, temperature, memory_used, disk_used, probe_ms
            FROM telemetry WHERE ts >= ? ORDER BY ts
            """,
            (since,),
        ).fetchall()
    if not rows:
        return {"hours": hours, "samples": 0, "incidents": 0}

    def average(field):
        values = [row[field] for row in rows if row[field] is not None]
        return round(sum(values) / len(values), 1) if values else None

    def percentage(field):
        values = [row[field] for row in rows if row[field] is not None]
        return round((sum(values) / len(values)) * 100, 1) if values else None

    incidents = 0
    previous = None
    for row in rows:
        state = (
            row["online"],
            row["control_ready"],
            row["parsec_ready"],
            row["fan_control"],
            row["codex"],
        )
        if previous:
            incidents += sum(before and not after for before, after in zip(previous, state))
        previous = state

    temperatures = [row["temperature"] for row in rows if row["temperature"] is not None]
    return {
        "hours": hours,
        "samples": len(rows),
        "incidents": incidents,
        "availability": percentage("online"),
        "bridge_availability": percentage("control_ready"),
        "cpu_average": average("cpu"),
        "gpu_average": average("gpu"),
        "temperature_average": average("temperature"),
        "temperature_peak": max(temperatures) if temperatures else None,
        "memory_average": average("memory_used"),
        "disk_average": average("disk_used"),
        "probe_average_ms": average("probe_ms"),
        "first_sample_at": rows[0]["ts"],
        "last_sample_at": rows[-1]["ts"],
    }


def read_audit(limit):
    with database() as connection:
        rows = connection.execute(
            """
            SELECT id, ts, action, ok, message, duration_ms
            FROM audit ORDER BY id DESC LIMIT ?
            """,
            (limit,),
        ).fetchall()
    return {"items": [dict(row) for row in rows]}


def monitor_loop():
    global LATEST_STATUS, LATEST_STATUS_VERSION
    while True:
        cycle_started = time.monotonic()
        status = capture_status()
        with STATUS_CONDITION:
            LATEST_STATUS = status
            LATEST_STATUS_VERSION += 1
            subscribers = STATUS_SUBSCRIBERS
            STATUS_CONDITION.notify_all()
        interval = 4 if subscribers else 15
        time.sleep(max(0.5, interval - (time.monotonic() - cycle_started)))


# --------------------------------------------------------------------------- #
# HTTP
# --------------------------------------------------------------------------- #


class Handler(BaseHTTPRequestHandler):
    # On reste en HTTP/1.0 (pas de keep-alive) : certaines réponses d'erreur partent
    # avant la lecture du corps de la requête, ce qui désynchroniserait une connexion réutilisée.
    server_version = "RemoteWake/5.0"

    def send_bytes(self, status, body, content_type, cache="no-store"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", cache)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; "
            "connect-src 'self'; img-src 'self' data: blob:; frame-ancestors 'none'; "
            "base-uri 'none'; form-action 'self'",
        )
        self.end_headers()
        self.wfile.write(body)

    def send_json(self, status, payload):
        self.send_bytes(
            status, json.dumps(payload, ensure_ascii=False).encode(), JSON_TYPE
        )

    def read_json(self):
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            raise ValueError("Requête invalide")
        if length < 2 or length > 2048:
            raise ValueError("Requête invalide")
        return json.loads(self.rfile.read(length))

    def guard_api(self):
        """Limite de débit puis authentification, pour toute route /api/*."""
        if rate_limited(self.client_address[0]):
            self.send_json(429, {"error": "Trop de requêtes, attends une minute."})
            return False
        if not authorized(self.headers.get("Authorization")):
            self.send_json(401, {"error": "Clé incorrecte"})
            return False
        return True

    def stream_events(self):
        """Flux SSE authentifié : état complet toutes les quatre secondes."""
        global STATUS_SUBSCRIBERS
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache, no-store, no-transform")
        self.send_header("X-Accel-Buffering", "no")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()

        started = time.monotonic()
        sequence = 0
        last_version = -1
        with STATUS_CONDITION:
            STATUS_SUBSCRIBERS += 1
            STATUS_CONDITION.notify_all()
        try:
            while time.monotonic() - started < 240:
                with STATUS_CONDITION:
                    STATUS_CONDITION.wait_for(
                        lambda: LATEST_STATUS_VERSION != last_version, timeout=20
                    )
                    version = LATEST_STATUS_VERSION
                    payload = dict(LATEST_STATUS) if LATEST_STATUS else None
                if not payload:
                    self.wfile.write(b": keepalive\n\n")
                    self.wfile.flush()
                    continue
                last_version = version
                sequence += 1
                payload["sequence"] = sequence
                payload["streamed_at"] = int(time.time() * 1000)
                frame = (
                    "retry: 2500\n"
                    f"id: {sequence}\n"
                    "event: status\n"
                    f"data: {json.dumps(payload, ensure_ascii=False, separators=(',', ':'))}\n\n"
                )
                self.wfile.write(frame.encode("utf-8"))
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            with STATUS_CONDITION:
                STATUS_SUBSCRIBERS = max(0, STATUS_SUBSCRIBERS - 1)
                STATUS_CONDITION.notify_all()

    def do_GET(self):
        parsed_url = urlsplit(self.path)
        path = parsed_url.path
        query = parse_qs(parsed_url.query)

        static = STATIC_ROUTES.get(path)
        if static:
            body, content_type, cache = static
            self.send_bytes(200, body, content_type, cache)
            return

        if path == "/health":
            self.send_json(200, {"ok": True})
            return

        if path == "/.well-known/assetlinks.json":
            try:
                with open(ASSETLINKS_FILE, "rb") as handle:
                    body = handle.read()
            except OSError:
                self.send_json(404, {"error": "Introuvable"})
                return
            self.send_bytes(200, body, JSON_TYPE, "public, max-age=3600")
            return

        if path == "/api/status":
            if not self.guard_api():
                return
            self.send_json(200, capture_status())
            return

        if path == "/api/events":
            if not self.guard_api():
                return
            self.stream_events()
            return

        if path == "/api/screen":
            self.handle_screen(query)
            return

        if path == "/api/history":
            if not self.guard_api():
                return
            try:
                minutes = int(query.get("minutes", ["60"])[0])
            except ValueError:
                minutes = 60
            if minutes not in (15, 60, 360, 1440, 10080):
                self.send_json(400, {"error": "Période non autorisée"})
                return
            self.send_json(200, read_history(minutes))
            return

        if path == "/api/summary":
            if not self.guard_api():
                return
            try:
                hours = int(query.get("hours", ["24"])[0])
            except ValueError:
                hours = 24
            if hours not in (1, 6, 24, 168):
                self.send_json(400, {"error": "Période non autorisée"})
                return
            self.send_json(200, read_summary(hours))
            return

        if path == "/api/audit":
            if not self.guard_api():
                return
            try:
                limit = int(query.get("limit", ["30"])[0])
            except ValueError:
                limit = 30
            self.send_json(200, read_audit(max(10, min(limit, 100))))
            return

        self.send_json(404, {"error": "Introuvable"})

    def read_json_large(self, limit=1_500_000):
        """Corps JSON pouvant contenir un fichier encodé (upload)."""
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            raise ValueError("Requête invalide")
        if length < 2 or length > limit:
            raise ValueError("Requête invalide")
        return json.loads(self.rfile.read(length))

    def handle_action(self):
        """Canal de pilotage riche : /api/action { action, args }."""
        if rate_limited_control(self.client_address[0]):
            self.send_json(429, {"error": "Trop de requêtes, ralentis un peu."})
            return
        if not authorized(self.headers.get("Authorization")):
            self.send_json(401, {"error": "Clé incorrecte"})
            return
        try:
            payload = self.read_json_large()
        except (ValueError, json.JSONDecodeError):
            self.send_json(400, {"error": "Requête invalide"})
            return

        action = payload.get("action") if isinstance(payload, dict) else None
        if action not in RICH_ACTIONS:
            self.send_json(400, {"error": "Action non autorisée"})
            return
        args = payload.get("args") if isinstance(payload.get("args"), dict) else {}

        # Gate rapide via l'état de fond (aucun arping par action : la latence doit
        # rester minimale pour le pilotage). Le canal SSH détecte lui-même une tour
        # éteinte en échouant vite.
        if LATEST_STATUS and not LATEST_STATUS.get("online"):
            self.send_json(409, {"online": False, "error": "La tour est éteinte, allume-la d'abord."})
            return

        started = time.monotonic()
        timeout = RICH_TIMEOUTS.get(action, 30)
        try:
            if action in CHANNEL_ACTIONS:
                try:
                    result, _ = pc_channel(action, args, timeout=timeout)
                except RuntimeError:
                    result = pc_action(action, args, timeout=timeout)
            else:
                result = pc_action(action, args, timeout=timeout)
        except RuntimeError as error:
            self.send_json(503, {"online": True, "ok": False, "error": str(error)})
            return

        if action not in READ_ONLY_ACTIONS:
            record_audit(
                action,
                result.get("ok", True),
                result.get("message") or result.get("error") or "Terminé",
                (time.monotonic() - started) * 1000,
            )

        self.send_json(200 if result.get("ok", True) else 500, {"online": True, **result})

    def handle_screen(self, query):
        """Trame d'écran (canal persistant). Renvoie l'image seulement si elle a changé."""
        if rate_limited_screen(self.client_address[0]):
            self.send_json(429, {"error": "Trop de trames."})
            return
        if not authorized(self.headers.get("Authorization")):
            self.send_json(401, {"error": "Clé incorrecte"})
            return
        if LATEST_STATUS and not LATEST_STATUS.get("online"):
            self.send_json(409, {"online": False, "error": "La tour est éteinte."})
            return

        def as_int(name, default):
            try:
                return int(query.get(name, [str(default)])[0])
            except (ValueError, TypeError):
                return default

        args = {
            "since": as_int("since", -1),
            "monitor": as_int("monitor", -1),
            "width": as_int("width", 1280),
            "fps": as_int("fps", 12),
        }
        try:
            header, image = pc_channel("Frame", args, timeout=15)
        except RuntimeError as error:
            self.send_json(503, {"ok": False, "error": str(error)})
            return
        # Le canal renvoie les octets JPEG bruts (efficace) ; base64 seulement pour le
        # lien téléphone, et image omise si la trame n'a pas changé.
        payload = {k: v for k, v in header.items() if k not in ("img_len", "id")}
        if image:
            payload["image"] = base64.b64encode(image).decode("ascii")
        self.send_json(200, payload)

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        if path not in ("/api/wake", "/api/control", "/api/action"):
            self.send_json(404, {"error": "Introuvable"})
            return

        if path == "/api/action":
            self.handle_action()
            return

        if not self.guard_api():
            return

        if path == "/api/wake":
            started = time.monotonic()
            set_manual_off(False)
            online = is_online()
            wake()
            message = (
                "Tour déjà allumée."
                if online
                else "Signal envoyé, démarrage en cours."
            )
            record_audit(
                "wake", True, message, (time.monotonic() - started) * 1000
            )
            self.send_json(
                200 if online else 202,
                {
                    "online": online,
                    "message": message,
                },
            )
            return

        try:
            payload = self.read_json()
        except (ValueError, json.JSONDecodeError):
            self.send_json(400, {"error": "Requête invalide"})
            return

        requested = payload.get("action") if isinstance(payload, dict) else None
        action = CONTROL_ACTIONS.get(requested)
        if not action or action == "Status":
            self.send_json(400, {"error": "Action non autorisée"})
            return
        started = time.monotonic()
        if not is_online():
            record_audit(
                requested,
                False,
                "La tour est éteinte.",
                (time.monotonic() - started) * 1000,
            )
            self.send_json(
                409, {"online": False, "error": "La tour est éteinte, allume-la d'abord."}
            )
            return
        manual_off = action == "Hibernate"
        try:
            if manual_off:
                set_manual_off(True)
            result = pc_control(action)
        except RuntimeError as error:
            if manual_off:
                set_manual_off(False)
            record_audit(
                requested,
                False,
                str(error),
                (time.monotonic() - started) * 1000,
            )
            self.send_json(503, {"online": True, "error": str(error)})
            return
        if manual_off and not result.get("ok", True):
            set_manual_off(False)
        record_audit(
            requested,
            result.get("ok", True),
            result.get("message") or result.get("error") or "Terminé",
            (time.monotonic() - started) * 1000,
        )
        self.send_json(
            200 if result.get("ok", True) else 500, {"online": True, **result}
        )

    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args), flush=True)


if __name__ == "__main__":
    init_database()
    threading.Thread(
        target=monitor_loop, name="gtol-blackbox", daemon=True
    ).start()
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
