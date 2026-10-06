# RoboGo design

- Date: 2026-10-06
- Status: design approved in chat by Czak; this file records it plus what the probes on the target machine showed. Implemented on the same day, see the plan and its execution notes.
- Repo: `C:\Users\user\GitHub\RoboGo`

## Goal

A small Windows 11 app that lets the user quickly build a robocopy command, run it, and track its progress.

## Decisions

| Topic | Decision |
|---|---|
| Scope | Quick one-offs only. No presets, queue, scheduling, installer or saved settings. |
| Tech | PowerShell + WPF. One script plus a double-click launcher. Nothing to install or compile. |
| Hosts | Works on Windows PowerShell 5.1 (built in) and PowerShell 7. |
| UI language | English. Polish may follow once the app is proven. No i18n layer now. |
| Tests | Dependency-free PowerShell test scripts, run on the target machine. No Pester. |

## Measured on the target machine

Machine: legion-slim, Windows 11 Pro, culture pl-PL, PowerShell 7.6.6 and 5.1, .NET desktop runtimes 8 and 10, no .NET SDK. Probed with real robocopy runs in a temp folder on 2026-10-06.

| Question | Finding | Consequence |
|---|---|---|
| Is piped output Unicode with `/UNICODE`? | No. It is a UTF-16 BOM followed by OEM code page 852 bytes. A CJK character came out as `?`. | Do not read stdout. |
| Is `/UNILOG:file` Unicode? | Yes, real UTF-16LE with CRLF. Polish and CJK names survive. | Progress is read by tailing a `/UNILOG` file. |
| Is the log flushed while copying? | Yes. The file grew every ~100 ms during a slowed copy. | Live progress from the log is viable. |
| Are labels localised on pl-PL? | No, robocopy prints English labels here. Only dates and Windows error texts are Polish. | Parser still relies on structure only, so other locales keep working. |
| File line shape | `TAB class TAB TAB size TAB path` | Two consecutive tabs identify a file line. |
| Folder line shape | `TAB class count TAB path\` | One tab, path ends with a backslash. |
| Progress updates | `CR  6.2%` ... `CR 100%` after each file line. Decimal point here, but robocopy uses a comma elsewhere in the same log. | Split on CR and LF, accept both separators. |
| Extra items | Class starts with `*` (`*EXTRA File`, `*EXTRA Dir`) and the path is under the destination. | Two structural signals for "not being copied". |
| Error lines | `2026/10/06 04:19:35 ERROR 32 (0x00000020) Copying File <path>`, then the file line is printed again on retry. | Detect by the `(0x........)` code; a repeated path is a retry, not a new file. |
| Summary with `/BYTES` | Rows Dirs, Files, Bytes with six integer columns. Columns widen for 12-digit byte counts and stay separated. | Totals and final numbers come from the summary by position. |
| List mode `/L` | The Copied column holds what would be copied. | The scan phase reads totals from a `/L` run with `/NFL /NDL /NJH`. |
| `/MT:8` | File lines and percent lines still appear, no folder lines. | Same parser, with a small pending list. |
| Exit codes | 0 nothing, 1 copied, 2 extras, 8 failures, 16 fatal (missing source). | Verdict is derived from the bit mask. |

## Files

| File | Purpose |
|---|---|
| `RoboGo.ps1` | The whole app: pure helpers, log parser, engine, window. ASCII only. |
| `RoboGo.cmd` | Launcher: starts the script without a console window, prefers `pwsh`, falls back to `powershell`. |
| `tests/TestHarness.ps1` | `Assert-Equal`, `Assert-True`, `Complete-Tests`. |
| `tests/Core.Tests.ps1` | Paths, quoting, command line, validation, formatting. |
| `tests/Parser.Tests.ps1` | Log parser, line splitter, verdict, using lines captured by the probes. |
| `tests/Engine.Tests.ps1` | Real robocopy runs in a temp folder: scan, run, multi-thread, mirror, failure, cancel. |
| `tests/Ui.Tests.ps1` | Loads the window, drives it, runs real copies through the controller, renders PNGs. Shown only far off screen. |
| `tests/Run-Tests.ps1` | Runs every suite in its own process of the current host. |
| `tests/Launcher.Smoke.ps1` | Starts `RoboGo.cmd`, drives a dry run and a copy in the real window through UI Automation, saves a picture, closes it. |

`RoboGo.ps1 -NoUI` only defines functions (tests dot-source it). `RoboGo.ps1 -SelfTest` runs a few built-in checks and loads the window without showing it.

## Window

One dark window, four numbered panels.

1. **Paths**: FROM and TO text boxes, Browse buttons, folder drag and drop. A dropped file selects its folder. A hint states that robocopy copies the contents of FROM, not the FROM folder itself.
2. **Options**: mode Copy / Mirror / Move as a segmented switch; Subfolders, Skip junctions, Keep newer files, Restartable; Threads, Retries, Wait; Skip files, Skip folders (separated by `;`); Extra switches (free text, also accepts file filters such as `*.jpg`).
3. **Command**: live preview with coloured tokens, destructive switches in red; Copy button; first validation problem; "Scan first" check box; Dry run, Run, Cancel.
4. **Progress**: segmented bar, percent, files, data, speed, ETA, current file, status line, raw log (hideable), Open log file.

## Command rules

- Paths are always quoted, and a quoted path never ends with a backslash (robocopy would read `\"` as an escaped quote). Drive roots are written unquoted as `D:\`.
- Copy: `/E` when Subfolders is on. Mirror: `/MIR`. Move: `/E /MOVE`, or `/MOV` without subfolders.
- `/MT:n` only when Threads is above 1. Default 8.
- `/R:2 /W:5` always, because robocopy defaults to 1,000,000 retries of 30 s each.
- `/XJ` on by default, `/XO` and `/Z` off by default.
- The preview shows the command the user could type. When RoboGo runs it, it appends `/BYTES /FP /UNILOG:"<temp log>"`, plus `/L` for a dry run and `/L /NFL /NDL /NJH` for the scan.

## Progress tracking

1. **Scan** (optional, on by default): a list-only run. Totals are the Copied column of the Files and Bytes summary rows.
2. **Run**: robocopy starts hidden. A 200 ms UI timer reads whatever was appended to the log, decodes UTF-16, splits it into lines and updates the state.
3. A file counts as copied when its `100%` line arrives. The running file contributes `size * percent`. A file that is replaced by another file line without reaching 100% (failed, skipped) is not counted.
4. With several threads the percent line is applied to the newest unfinished file. This is an estimate; the summary corrects the final numbers.
5. Speed is the byte delta over the last 5 seconds. ETA is remaining bytes divided by speed.
6. Without a scan there is no percent or ETA: the bar sweeps and only counters are shown.
7. The bar never shows 100% before robocopy has exited successfully.

## Safety

- Mirror and Move are drawn in red and need a confirmation that names both folders and points at Dry run.
- `/MIR`, `/PURGE`, `/MOV`, `/MOVE` typed into Extra are treated the same way.
- Validation blocks: missing source, empty paths, identical folders, destination inside source, source inside destination for Mirror, out-of-range numbers, and Extra switches that break log parsing (`/LOG`, `/UNILOG`, `/NFL`, `/NS`, `/NC`, `/NP`, `/NJS`, `/QUIT`, `/MON`, `/MOT`, `/JOB`, `/SAVE`).
- No elevation. `/B` and `/COPYALL` are not offered as check boxes.
- Cancel kills robocopy. Closing the window during a run asks first.

## Error handling

- Every event handler is wrapped: an unexpected error lands in the status line instead of killing the window.
- A fatal scan (exit 16 or more) ends the job and shows the scan output.
- A scan without a readable summary degrades to a run without totals.
- Startup failure shows a message box, because the console is hidden.

## Visual direction

Industrial instrument panel. Near-black surfaces, one amber accent, red only for destructive things, monospace type (Cascadia Mono, fallback Consolas) because the subject is a command line. The two elements meant to be remembered: the syntax-coloured command "tape" and the segmented amber meter. Fonts are limited to what Windows 11 ships, since the app must stay a single script.

## Out of scope

Presets, job queue, scheduling, installer, saved settings, elevation, localisation, a compiled executable.
