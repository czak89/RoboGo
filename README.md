# RoboGo

Robocopy, minus the typing. A small Windows 11 app that builds a robocopy command, runs it, and shows live progress.

## Start

1. Run `build.cmd` once. It creates `RoboGo.exe`, a small launcher, with the C# compiler that ships with Windows.
2. Start the app with `RoboGo.exe`. Pin it or make a shortcut if you like.

`RoboGo.cmd` starts the app too and needs no build step, but a console window flashes for a moment.

Nothing to install: the app uses only what Windows ships (PowerShell, WPF, robocopy). It runs on Windows PowerShell 5.1 and on PowerShell 7, and picks PowerShell 7 when it is on the PATH.

## Portable

The folder is the app. RoboGo writes only two things, both next to itself:

| What | Where |
|---|---|
| Settings (language, Keep log file) | `settings.json` |
| Logs you chose to keep | `logs\` |

While a job runs, robocopy writes a working log to `%TEMP%\RoboGo`. It is deleted when the job ends. Nothing goes to `%APPDATA%` or the registry. Move or copy the folder and everything comes along. If the folder is read-only, the app still runs and only the settings are not remembered.

## Use

1. **Paths**: type, paste, browse or drop the FROM and TO folders. Robocopy copies what is inside FROM into TO. It does not create the FROM folder itself.
2. **Options**: see the table below. Empty fields show an example.
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

### The ? button

`?` next to EXTRA opens a panel with two lists.

- **Recommended setups** set THREADS, Restartable and the switches that belong to the setup. Whatever else you typed into EXTRA stays.

| Setup | Threads | Restartable | Switches |
|---|---|---|---|
| NAS or network share | 8 | on | `/FFT` |
| A few very large files | 1 | off | `/J` |
| Many small files between fast drives | 16 | off | |
| USB stick or SD card (FAT, exFAT) | 1 | off | `/FFT /DST` |
| Back to the defaults | 8 | off | setup switches removed |

- **Useful switches**: tick one to add it to EXTRA, untick it to remove it. The boxes follow what you type. Values such as `7` in `/MAXAGE:7` are examples; edit them in the EXTRA field.

`*.jpg`, `/XA:SH`, `/MAXAGE:7`, `/MINAGE:30`, `/MAX:104857600`, `/LEV:2`, `/J`, `/FFT`, `/DST`, `/DCOPY:DAT`, `/COMPRESS`, `/IPG:50`, `/SL`, `/CREATE`, `/IS`

## Progress and logs

- With **Scan first** on, RoboGo runs the command once in list-only mode to count files and bytes, then runs it for real. That is what makes percent and ETA possible.
- With it off there is no percent: the bar sweeps and you get counters and speed.
- With several threads the percent is an estimate while copying. The final numbers come from robocopy's own summary.
- The log box shows robocopy's output as it comes, the newest 5,000 lines of the job. COPY LOG puts it on the clipboard, HIDE LOG shrinks the window.
- **Keep log file** is off by default, so a job leaves no file behind. Turn it on and the full log of every job is saved to `logs\` next to the app; OPEN LOG then opens the one of the last job.
- At every start, logs older than 30 days are deleted from `logs\` and from `%TEMP%\RoboGo`.

How it works underneath: when it runs a job, RoboGo adds `/BYTES /FP /UNILOG:"<working log>"` to the command shown in the preview and reads that file as robocopy writes it. The file is the only robocopy output that keeps every character of a file name intact.

## Language

The button in the top right shows the current language and switches to the next one. The choice is remembered.

- English is built in. Every `lang\<code>.json` adds a language.
- `lang\pl.json` is there with every text, still in English. Translate the values, keep the keys and placeholders such as `{0}`.
- `tools\Export-Language.ps1 -Code de -Name Deutsch` creates a file for another language, and refreshes an existing one after an update without losing what was translated.
- Robocopy's own output is not translated.

## Safety

- MIRROR and MOVE are shown in red and ask before they run. The same goes for `/MIR`, `/PURGE`, `/MOV` and `/MOVE` typed into Extra.
- RoboGo refuses to run when the source is missing, when both folders are the same, when TO is inside FROM, or when a MIRROR would delete its own source.
- These switches are refused in Extra because they break the progress display or never exit: `/LOG`, `/UNILOG`, `/NFL`, `/NS`, `/NC`, `/NP`, `/NJS`, `/QUIT`, `/MON`, `/MOT`, `/JOB`, `/SAVE`.
- `/IPG` is refused with more than 1 thread, because robocopy itself rejects that combination.

## Limits

- No elevation. Switches that need an administrator (`/B`, `/COPYALL`) only work if you start RoboGo elevated and type them into Extra.
- One job at a time. No presets, no queue. Paths and options are not saved between sessions.
- `RoboGo.exe` is not signed. When pinned to the taskbar, the running window gets a button of its own next to the pin.

## Tests

```
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
```

```
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
```

The suites run real robocopy jobs inside a fresh folder under `%TEMP%` and delete it afterwards. They point the app at a throwaway settings folder through the `ROBOGO_HOME` environment variable, and they do not touch the clipboard. `tests\Ui.Tests.ps1` shows nothing on screen and writes screenshots to `%TEMP%\RoboGoShots`.

`tests\Launcher.Smoke.ps1` is run by hand. It builds `RoboGo.exe` when needed, starts it the way Explorer does and checks that no console window shows up, then drives the real window: language button, help panel, a dry run, a copy without and with a kept log. Windows are on screen for about twenty seconds. Leave mouse and keyboard alone meanwhile: the help panel closes when another window takes the focus. With `-Mouse` the test also clicks the `?` button with the real pointer.

A quick check that needs only the script itself:

```
powershell -NoProfile -ExecutionPolicy Bypass -File RoboGo.ps1 -SelfTest
```

## Files

| File | What it is |
|---|---|
| `RoboGo.ps1` | The app |
| `build.cmd` | Builds `RoboGo.exe` from `launcher\RoboGoLauncher.cs` |
| `RoboGo.cmd` | Starts the app without the launcher |
| `RoboGo.ico` | Icon of the launcher and the window, drawn by `tools\New-RoboGoIcon.ps1` |
| `lang\` | Language files |
| `tools\` | Language export, icon drawing |
| `tests\` | Test suites |
| `docs\superpowers\` | Designs and implementation plans |
