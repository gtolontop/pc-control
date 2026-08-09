PCMode profile switcher
=======================

Main folder:
  C:\Users\teamr\Desktop\PCMode

Use the .bat files in that Desktop folder:

01 Normal
- Balanced Windows plan.
- Normal GPU clocks.
- FanControl Default profile.
- Good default when you are not sleeping and not forcing max gaming mode.

02 Perf Gaming
- High performance Windows plan.
- CPU max 100%, efficient aggressive boost, EPP 20.
- GPU power limit 320W, clocks reset to normal NVIDIA boost behavior.
- FanControl Default profile.
- Does not open Discord.

03 Sleep Max Silence 0-5 joueurs
- Maximum silence.
- CPU max 30%, boost disabled, EPP 100.
- GPU power limit 150W, lowest practical clocks.
- FanControl Silent profile.
- Stops Discord and DiscordPTB. Chrome stays open so browser audio can keep playing.
- Notifications off, screens off.

04 Sleep Server 5-20 joueurs
- Quiet night mode with more CPU headroom.
- CPU max 55%, boost disabled, EPP 85.
- GPU kept low.
- FanControl Silent profile.
- Stops Discord and DiscordPTB. Chrome stays open so browser audio can keep playing.
- Notifications off, screens off.

05 Sleep Server 20+ joueurs
- Best night profile if many players may be online.
- CPU max 80%, efficient boost enabled, EPP 65.
- GPU kept low.
- FanControl Silent profile.
- More performance, potentially more fan noise.

06 Night Mode ON
- Remote-safe night mode only.
- Keeps the PC awake, keeps Parsec available, updates Parsec remote config, and turns displays off.
- Does not change CPU/GPU/FanControl profile by itself.

07 Night Mode OFF
- Wakes/restores displays and keeps Parsec available.
- Use this when you come back to the physical PC.

08 Parsec Repair
- Re-applies Parsec keep-alive and remote config without restarting Parsec.

90 Status
- Prints current power plan, RAM, CPU, GPU, and top RAM groups.

91 Open Logs
- Opens C:\PCMode\logs.

99 Rollback Remote Setup
- Re-enables displays and restores the last backed up Parsec config.
- Use this if local display recovery is needed.

Implementation:
- C:\PCMode\pcmode.ps1 is the central profile script.
- C:\PCMode\perf.ps1 reads a requested profile from:
  %LOCALAPPDATA%\PCMode\requested-mode.txt
  then calls pcmode.ps1.
- Existing scheduled task PCMode_Perf is used as the elevated runner.
- Existing scheduled task PCMode_Sleep still works and maps to Sleep.
- Sleep profiles call C:\PCMode\night-mode-on.ps1 for the remote-safe display/Parsec part.

Logs:
- C:\PCMode\logs\last-perf.log
- C:\PCMode\logs\last-normal.log
- C:\PCMode\logs\last-sleep.log
- C:\PCMode\logs\last-sleepserver.log
- C:\PCMode\logs\last-sleepheavy.log
- C:\PCMode\logs\last-status.log

Rule of thumb:
- Empty or nearly empty server overnight: 03.
- Friends may join overnight: 04.
- 20+ players or heavy plugins/chunks: 05.
- Back at the PC: 01 or 02.
