# RoboGo

Robocopy, minus the typing. A small Windows 11 app that builds a robocopy command, runs it, and shows live progress.

## Start

Double-click `RoboGo.cmd`. Nothing to install: it uses only what Windows ships (PowerShell, WPF, robocopy). It runs on Windows PowerShell 5.1 and on PowerShell 7, and picks PowerShell 7 when it is there.

## Use

1. **Paths**: type, paste, browse or drop the FROM and TO folders. Robocopy copies what is inside FROM into TO. It does not create the FROM folder itself.
2. **Options**: see the table below.
3. **Command**: the preview updates as you go. COPY puts it on the clipboard.
4. **Dry run** lists what would happen and changes nothing. **Run** does it. **Cancel** stops robocopy; files already copied stay.

| Control | Switch | Default |
|---|---|---|
| COPY | none, or `/E` with Subfolders | selected |
| MIRROR | `/MIR` (deletes what is extra in TO) | |
| MOVE | `/E /MOVE`, or `/MOV` without Subfolders (deletes from FROM) | |
| Subfolders | `/E` | on |
| Skip junctions | `/XJ` | on |
| Keep newer files | `/XO` | off |
| Restartable | `/Z` | off |
| Threads | `/MT:n`, left out when 1 | 8 |
| Retries, Wait | `/R:n /W:n` | 2, 5 |
| Skip files, Skip folders | `/XF`, `/XD`, items separated by `;` | empty |
| Extra | added as typed, also file filters such as `*.jpg` | empty |

Robocopy's own default is one million retries with 30 seconds between them. RoboGo always sets `/R` and `/W`.

## How progress works

- With **Scan first** on, RoboGo runs the command once in list-only mode to count files and bytes, then runs it for real. That is what makes percent and ETA possible.
- With it off there is no percent: the bar sweeps and you get counters and speed.
- When it runs a job, RoboGo adds `/BYTES /FP /UNILOG:"<log file>"` to the command shown in the preview and reads that log file as robocopy writes it. Logs are kept in `%TEMP%\RoboGo` (the newest 20).
- With several threads the percent is an estimate while copying. The final numbers come from robocopy's own summary.

## Safety

- MIRROR and MOVE are shown in red and ask before they run. The same goes for `/MIR`, `/PURGE`, `/MOV` and `/MOVE` typed into Extra.
- RoboGo refuses to run when the source is missing, when both folders are the same, when TO is inside FROM, or when a MIRROR would delete its own source.
- These switches are refused in Extra because they break the progress display or never exit: `/LOG`, `/UNILOG`, `/NFL`, `/NS`, `/NC`, `/NP`, `/NJS`, `/QUIT`, `/MON`, `/MOT`, `/JOB`, `/SAVE`.

## Limits

- No elevation. Switches that need an administrator (`/B`, `/COPYALL`) only work if you start RoboGo elevated and type them into Extra.
- One job at a time. No presets, no queue, nothing is saved between sessions.
- English only for now.

## Tests

```
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
```

```
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
```

The suites run real robocopy jobs inside a fresh folder under `%TEMP%` and delete it afterwards. `tests\Ui.Tests.ps1` shows nothing on screen and writes screenshots to `%TEMP%\RoboGoShots`. `tests\Launcher.Smoke.ps1` starts the real app through `RoboGo.cmd`, drives a dry run and a copy in a temp folder through UI Automation, saves a picture of the window and closes it. The window is on screen for about ten seconds.

A quick check that needs only the script itself:

```
powershell -NoProfile -ExecutionPolicy Bypass -File RoboGo.ps1 -SelfTest
```

## Files

| File | What it is |
|---|---|
| `RoboGo.cmd` | Launcher |
| `RoboGo.ps1` | The app |
| `tests\` | Test suites |
| `docs\superpowers\` | Design and implementation plan |
