# PCMode Remote / Parsec Setup

## Diagnostic

- Parsec is installed per-computer in `C:\Program Files\Parsec`.
- The Windows service `Parsec` exists, runs as `LocalSystem`, and is set to `Automatic`.
- Parsec Virtual Display Adapter is installed.
- The current stable physical audio endpoint is Realtek speakers.
- NVIDIA/monitor audio endpoints are present and should not be preferred for remote sessions because they can disappear when displays sleep.
- No VB-Cable/Voicemeeter-style virtual render device is currently detected.

## Chosen behavior

- The PC never enters full sleep while night mode is active.
- Night mode turns displays off without muting Windows.
- Parsec is kept enabled and available.
- Parsec physical output pins are removed from the managed config so it can use virtual/fallback displays instead of waking physical monitors.
- If a virtual audio render device is later installed, the scripts will prefer it for Parsec capture and stop relying on host speaker mute.
- Without a virtual audio device, Parsec host mute remains enabled so sound should not play physically on the tower during owner sessions.
- Hard disabling physical monitors during an active Parsec stream is disabled. On this machine it causes DXGI capture loss and freeze loops.

## Stable reality

The stable daily setup is:

- `01 Normal`
- `02 Perf Gaming`
- `03 Mode Nuit`

`03 Mode Nuit` is intentionally soft: it lowers noise/power and turns displays off, but remote Parsec input may wake physical displays because Windows treats Parsec input like local mouse/keyboard input.

The clean way to make physical displays stay off during remote use is to have Parsec capture a virtual/dummy display from the start. That means one of:

- Parsec Warp/Teams Virtual Displays + Privacy Mode working on the account.
- A physical HDMI/DisplayPort dummy plug and Parsec pinned to that dummy display.
- A separate stable virtual display solution that Windows treats as the active display before the stream starts.

Do not use live monitor disable/enable loops during Parsec sessions on this PC.

## Main scripts

- `C:\PCMode\night-mode-on.ps1`
- `C:\PCMode\night-mode-off.ps1`
- `C:\PCMode\parsec-repair.ps1`
- `C:\PCMode\rollback-remote-setup.ps1`
- `C:\PCMode\audit-parsec-host.ps1`
- `C:\PCMode\install-remote-tasks.ps1`
- `C:\PCMode\remote-mode.config.json`

## Admin commands

Open PowerShell as Administrator, then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\PCMode\install-remote-tasks.ps1"
```

Optional aggressive monitor disable, only if simple display-off is not enough:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\PCMode\night-mode-on.ps1" -Profile ManualNight -DisablePhysicalMonitors
```

Emergency rollback:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\PCMode\rollback-remote-setup.ps1"
```

## Test procedure

1. Run `C:\PCMode\audit-parsec-host.ps1`.
2. Run `C:\PCMode\parsec-repair.ps1`.
3. Restart Parsec only when you can reconnect if needed:
   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\PCMode\parsec-repair.ps1" -RestartParsec`
4. From the laptop, connect through Parsec.
5. Run `06 Night Mode ON.bat` from the Desktop `PCMode` folder, or use the existing Sleep profile.
6. Start Spotify/Chrome audio and verify it is heard on the Parsec client.
7. Verify the physical monitors stay off.
8. Run `07 Night Mode OFF.bat` when back at the physical PC.

## If local displays are lost

1. Press `Win+Ctrl+Shift+B` to reset the graphics driver.
2. Press `Win+P`, then press `Down`, then `Enter` a few times to cycle display modes.
3. From Parsec, run `C:\PCMode\rollback-remote-setup.ps1`.
4. If needed, open PowerShell as Administrator locally and run the emergency rollback command above.

## Audio note

For the cleanest remote audio, install a stable virtual render device such as VB-Cable, then set `PreferredVirtualAudioPattern` in `C:\PCMode\remote-mode.config.json` to match its name. After that, run `C:\PCMode\parsec-repair.ps1 -RestartParsec` once.
