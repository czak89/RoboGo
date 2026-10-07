# AGENTS.md

Rules for AI coding agents (and people) who change this repository.

## What this is

RoboGo is a small Windows app that builds a `robocopy` command, runs it and shows the progress. One PowerShell script with a WPF window, a tiny C# launcher, no dependencies beyond Windows 10 or 11.

## Layout

| Path | What it is |
|---|---|
| `RoboGo.ps1` | The whole app. Sections, in this order: 0 texts, languages, settings; 1 pure helpers (paths, command line, validation, Send to shortcut, native helper type); 2 log parser and verdict; 3 engine (start robocopy, follow its log); 4 window; entry point. |
| `launcher/RoboGoLauncher.cs` | Starts `RoboGo.ps1` without a console window. `build.cmd` compiles it to `RoboGo.exe` and packs the script, the icon and `lang/*.json` into it as resources. Without a `RoboGo.ps1` next to it the exe unpacks them to `%TEMP%\RoboGo\app-<hash>` and names itself in `ROBOGO_EXE`. The exe is not committed. |
| `RoboGo.cmd` | Starts the app without the launcher. |
| `lang/<code>.json` | Translations. `en.json` is the reference for translators: the app never reads it, and a test keeps it identical to the built-in texts. |
| `tools/Sign-RoboGo.ps1` | Signs the exe with a certificate from the environment. Used by the workflow. |
| `.github/workflows/release.yml` | Tests, build, optional signing; a tag `v<version>` publishes a GitHub Release. |
| `tests/` | `Core`, `Parser`, `Engine`, `Ui`, `Package` suites, plus `Launcher.Smoke.ps1`, which is run by hand. |
| `docs/superpowers/` | Design specs and implementation plans, one pair per version. |

## Rules

1. **Both PowerShell hosts.** Everything runs on Windows PowerShell 5.1 and on PowerShell 7. No syntax or cmdlet that only one of them has. C# inside `Add-Type` and in the launcher stays within C# 5, because the compiler that ships with Windows is that old.
2. **ASCII only** in every file except `lang/*.json`. No em dashes or en dashes. A character outside ASCII is written as `[char]0x....` in code.
3. **Every text goes through the table.** Whatever the app shows comes from `$script:RoboText` through `Get-RoboText`. The XAML holds no texts. A new or changed text needs the key in the table, `lang/en.json` exported again (`tools/Export-Language.ps1 -Code en -Name English`) and a translation in every other `lang/*.json`. Tests compare keys, placeholders and leading switches.
4. **No plural forms.** Counts are written as `Label: number.` (`Files copied: 13.`), because plural rules differ between languages. A test fails on any text that contains `(s)`.
5. **No logic depends on a text.** Decisions use data (exit codes, parsed numbers, switches), never the wording of a message.
6. **Robocopy output is parsed by structure**, not by words: tabs, the percent sign, the hex error code, six-column summary rows. Robocopy's labels are English even on a Polish system, its messages are not.
7. **Numbers are formatted with the invariant culture.**
8. **The app writes only into its own folder** (`settings.json`, `logs\`; for the single-file exe that is the folder of the exe) and `%TEMP%\RoboGo`. The one exception is the Send to shortcut, and only after the user switched it on.
9. **The mode is never saved.** Every start is COPY. Do not add MIRROR or MOVE to what is remembered.
10. **Anything that deletes asks first** and is shown in red.
11. **No secrets in the repository.** Certificates, passwords and tokens come from GitHub Actions secrets through the environment, and no script prints them.
12. **Sounds are played by the app itself** (`Invoke-RoboSound`, `PlaySound` with an event of the sound scheme). Not through `[System.Media.SystemSounds]` or `MessageBeep`: those hand the request to Windows, which can report success and stay silent.

## Tests

Write the test first, watch it fail for the right reason, then write the code.

```
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File RoboGo.ps1 -SelfTest
```

- A change is done when all five suites pass on both hosts. `-Filter Ui` runs one suite.
- Tests stay off the desktop of whoever runs them. They set `ROBOGO_HOME` (settings, kept logs, languages) and `ROBOGO_SENDTO` (the Send to shortcut) to temp folders, and they replace these functions: `Set-RoboClipboard`, `Confirm-RoboGo` (every yes/no question), `Invoke-RoboAttention` (flash and sound), `Invoke-RoboSound`, and in the window tests `Get-RoboFreeSpace`. New code that would open a dialog, play a sound or touch the clipboard goes through one of these.
- Window tests never open a popup and never activate a window. They render to PNG files in `%TEMP%\RoboGoShots`; look at them after changing the layout.
- `tests\Launcher.Smoke.ps1` starts the real app and shows windows for about half a minute. Run it after changes to the launcher, the start-up path, popups or anything UI Automation touches. Nobody should use mouse or keyboard meanwhile.
- Real robocopy jobs run only inside fresh folders under `%TEMP%`, and every test removes what it created.

## Build

```
build.cmd /q
```

Needs only the .NET Framework 4 compiler that is part of Windows. The exe contains the script as it was at build time, so build again before you hand the exe to someone.

## Release

The version lives in two places that must agree: `$script:RoboGoVersion` in `RoboGo.ps1` and the two `Assembly...Version` lines in `launcher/RoboGoLauncher.cs` (the `Package` suite compares them). A tag `v<version>` on `main` makes the workflow publish the release; the workflow refuses a tag that does not match.

## Commits

Small commits, imperative subject with a type prefix (`feat:`, `fix:`, `test:`, `docs:`), the why in the body. A design spec and a plan in `docs/superpowers/` come before a feature.
