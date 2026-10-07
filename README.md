# RoboGo

Robocopy, minus the typing. A small Windows 11 app that builds a robocopy command, runs it, and shows live progress.

- One window: two folders, a few options, the command as you build it, RUN.
- Progress with percent, speed and ETA, in the window and on the taskbar button.
- Nothing to install and nothing left behind: the folder is the app.

## Start

1. Run `build.cmd` once. It creates `RoboGo.exe`, a small launcher, with the C# compiler that ships with Windows.
2. Start the app with `RoboGo.exe`.

`RoboGo.cmd` starts the app too and needs no build step, but a console window flashes for a moment.

The app uses only what Windows ships (PowerShell, WPF, robocopy). It runs on Windows PowerShell 5.1 and on PowerShell 7, and picks PowerShell 7 when it is on the PATH.

### Pin it to the taskbar

Start RoboGo, right-click **its button on the taskbar** and choose Pin to taskbar. The pin then starts `RoboGo.exe` and shares one button with the window.

A pin made from `RoboGo.exe` in Explorer works as well, but Windows shows the running window next to it as a second button. If you have such a pin, unpin it and pin the running window instead.

## Portable

RoboGo writes only two things, both next to itself:

| What | Where |
|---|---|
| Settings: language, Keep log file, log limits, the fields of the last session, recent folders, window position | `settings.json` |
| Logs you chose to keep | `logs\` |

While a job runs, robocopy writes a working log to `%TEMP%\RoboGo`. It is deleted when the job ends. Nothing goes to `%APPDATA%` or the registry. Move or copy the folder and everything comes along. If the folder is read-only, the app still runs and only forgets its settings.

The one exception is opt-in: the SEND TO button, see below.

## Use

1. **Paths**: type, paste, browse or drop the FROM and TO folders. Robocopy copies what is inside FROM into TO. It does not create the FROM folder itself.
2. **Options**: see the table below. Empty fields show an example.
3. **Command**: the preview updates as you go. COPY puts it on the clipboard. A long command shows its first two lines; SHOW ALL opens the rest.
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

### What is remembered

- The fields come back as you left them: both folders, every option, Scan first. They are saved when a job starts and when you close the window.
- **The mode does not come back.** Every start is COPY, so a MIRROR or MOVE from last time can never delete anything by reflex.
- The small arrow next to each BROWSE lists the folders of your last ten jobs. The last row empties the lists.
- The window opens where you closed it, if that place is still on a screen.

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

### Send to RoboGo

SEND TO in the top right puts RoboGo into the Send to menu of Explorer. Right-click a folder, Send to, RoboGo: the app opens with that folder in FROM and an empty TO. Click SEND TO again to take it out.

The shortcut for that menu lives in your Windows profile. It is the only thing RoboGo ever writes outside its own folder, and only after you clicked. If you move the RoboGo folder, the next start repairs the shortcut.

Dropping a folder on `RoboGo.exe` does the same as Send to.

## Progress and logs

- With **Scan first** on, RoboGo runs the command once in list-only mode to count files and bytes, then runs it for real. That is what makes percent and ETA possible.
- With it off there is no percent: the bar sweeps and you get counters and speed.
- With several threads the percent is an estimate while copying. The final numbers come from robocopy's own summary.
- **Taskbar**: the button shows the progress, turns yellow when errors appear and red when the job failed. When a job ends while you are in another window, the button flashes and Windows plays a sound.
- **Free space**: after the scan RoboGo compares what the job needs with what the destination has free, on a drive or a network share. Too little room asks whether to run anyway. Without Scan first there is no check.
- The log box shows robocopy's output as it comes, the newest 5,000 lines of the job. COPY LOG puts it on the clipboard, HIDE LOG shrinks the window.
- **Failed files**: when something could not be copied, `FAILED: n` appears under COPY LOG. It switches the log box to the failures only: what failed, the error code and what Windows said. FULL LOG switches back. COPY LOG copies whichever is shown.
- **Keep log file** is off by default, so a job leaves no file behind. Turn it on and the full log of every job is saved to `logs\` next to the app; OPEN LOG then opens the one of the last job.
- At every start RoboGo tidies up `logs\` and `%TEMP%\RoboGo`, each folder on its own. See the next section.

### Log limits

Three rules, applied in this order at every start:

1. Logs older than `LogMaxDays` are deleted.
2. Logs bigger than `LogFileMaxMB` are deleted, whatever their age.
3. While the logs that are left are bigger than `LogMaxMB` together, the oldest one is deleted.

| Key in `settings.json` | Default | Limit for |
|---|---|---|
| `LogMaxDays` | 30 | the age of a log, in days |
| `LogFileMaxMB` | 50 | one log |
| `LogMaxMB` | 100 | all logs of one folder together |

- `settings.json` is written at the first start. Change the numbers there while RoboGo is closed. Whole numbers from 1 to 1,000,000 count; anything else gives the default.
- 1 MB is 1,048,576 bytes. Robocopy writes roughly 200 to 300 bytes per file, so 50 MB is a job of about 200,000 files.
- A kept log that is bigger than `LogFileMaxMB` stays until you close RoboGo, and the log box tells you that the next start removes it. Raise the limit if you want to keep such logs.
- A log that a program still has open is never deleted, so a second RoboGo window in the middle of a job is safe.

How it works underneath: when it runs a job, RoboGo adds `/BYTES /FP /UNILOG:"<working log>"` to the command shown in the preview and reads that file as robocopy writes it. The file is the only robocopy output that keeps every character of a file name intact.

## Language

The button in the top right shows the current language and switches to the next one. The choice is remembered.

- English is built in. Every `lang\<code>.json` adds a language.
- `lang\pl.json` is there with every text, still in English. Translate the values, keep the keys and placeholders such as `{0}`.
- No text depends on a number being one or many. Counts are written as `Files copied: 13.`, so a translation never needs plural forms.
- `tools\Export-Language.ps1 -Code de -Name Deutsch` creates a file for another language, and refreshes an existing one after an update without losing what was translated.
- Robocopy's own output is not translated.

## Safety

- MIRROR and MOVE are shown in red and ask before they run. The same goes for `/MIR`, `/PURGE`, `/MOV` and `/MOVE` typed into Extra.
- The mode is never remembered between sessions.
- RoboGo refuses to run when the source is missing, when both folders are the same, when TO is inside FROM, or when a MIRROR would delete its own source.
- These switches are refused in Extra because they break the progress display or never exit: `/LOG`, `/UNILOG`, `/NFL`, `/NS`, `/NC`, `/NP`, `/NJS`, `/QUIT`, `/MON`, `/MOT`, `/JOB`, `/SAVE`.
- `/IPG` is refused with more than 1 thread, because robocopy itself rejects that combination.

## Limits

- No elevation. Switches that need an administrator (`/B`, `/COPYALL`) only work if you start RoboGo elevated and type them into Extra.
- One job at a time. No named presets, no queue.
- `RoboGo.exe` is not signed.

## Tests

```
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
```

```
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
```

The suites run real robocopy jobs inside a fresh folder under `%TEMP%` and delete it afterwards. They keep off your desktop: settings and the Send to shortcut go to throwaway folders (`ROBOGO_HOME`, `ROBOGO_SENDTO`), and nothing touches the clipboard, opens a dialog or plays a sound. `tests\Ui.Tests.ps1` shows nothing on screen and writes screenshots to `%TEMP%\RoboGoShots`.

`tests\Launcher.Smoke.ps1` is run by hand. It builds `RoboGo.exe` when needed, starts it the way Explorer does and checks that no console window shows up, then drives the real window: fields that survive a restart, language button, Send to, help panel, a dry run, a copy without and with a kept log, recent folders, a folder handed to the launcher. Windows are on screen for about half a minute. Leave mouse and keyboard alone meanwhile: a panel closes when another window takes the focus. With `-Mouse` the test also clicks the `?` button with the real pointer.

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
| `AGENTS.md`, `CLAUDE.md` | Rules for AI coding agents that work on this repository |

## License

MIT, see `LICENSE.md`. Free for everyone to use, change and share. The software is provided as is, without warranty of any kind: check with DRY RUN before you let it delete anything.
