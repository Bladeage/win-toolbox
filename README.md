# win-toolbox

[![CI](https://github.com/Bladeage/win-toolbox/actions/workflows/ci.yml/badge.svg)](https://github.com/Bladeage/win-toolbox/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![PowerShell 5.1 | 7](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE?logo=powershell&logoColor=white)

Windows helper scripts in one menu. One line in PowerShell, no install, nothing left behind.

```powershell
irm https://menu.geyer.zone | iex
```

Open **PowerShell** (no admin needed), paste the line, pick a tool. The menu asks for
administrator rights (UAC) only when a tool needs them and then re-launches itself.

## Tools

| Key | Tool | What it does |
|---|---|---|
| 1 | Activate Windows / Office | [Microsoft Activation Scripts](https://massgrave.dev) |
| 2 | Windows Update | Installs every pending update via [PSWindowsUpdate](https://www.powershellgallery.com/packages/PSWindowsUpdate) (auto-reboot) |
| 3 | Install / repair WinGet | [winget-install](https://github.com/asheroto/winget-install) by asheroto |
| 4 | Software Setup | Menu-driven winget installer: profiles **Runtimes / Standard / Gaming / Technician**, 250-app catalog in 11 categories, search, save/load selections (file or URL), dry run, upgrade mode, log + CSV report |
| 5 | Office Tool Plus | [officetool.plus](https://officetool.plus) |
| 6 | WinUtil | [Chris Titus Tech's Windows Utility](https://christitus.com/win) |
| 7 | WinScript | [flick9000/winscript](https://github.com/flick9000/winscript) |
| 8 | AdwCleaner | Downloads, runs and removes [Malwarebytes AdwCleaner](https://www.malwarebytes.com/adwcleaner) |
| 9 | Harden System Security | [HotCakeX's hardening app](https://github.com/HotCakeX/Harden-Windows-Security/wiki/Harden-System-Security) from the Microsoft Store (Windows 11 22H2+) |
| i | Inventory | Hardware / BIOS / OS / CPU / RAM / disks / GPU / monitors / network / battery + installed software into CSV (technician tool, German CSV column names) |
| t | Clean Traces | Remove the technician's working traces (shell history, Run/address-bar/Recent, temp, recycle bin), **dry run by default** |

`G` switches to an `Out-GridView` picker, `Q`/`Esc` quits. The menu asks for elevation (UAC) when
needed and re-launches itself. Works in Windows PowerShell 5.1 and PowerShell 7.

`G` switches to an `Out-GridView` picker, `Q`/`Esc` quits.

## Before you run it

`irm <url> | iex` downloads a script and runs it right away. Please read what you run:

- **Look first.** `irm https://menu.geyer.zone` without `| iex` prints the script instead of
  running it. Every script is also readable in [`dist/`](dist/).
- **Third-party tools run their own code.** Keys 1, 3, 5, 6 and 7 fetch and run scripts from
  their upstream projects (links in the table). The menu shows the URL before it runs them.
  Those projects are not part of win-toolbox and keep their own licenses. You are responsible
  for using them in line with your licenses and local law.
- **Some tools change the system.** Windows Update can reboot on its own, Software Setup
  installs software, Clean Traces deletes files (dry run by default).

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 (built in) or PowerShell 7
- Internet access
- Harden System Security needs Windows 11 22H2 or newer

## Single tools

Every tool is also published as a standalone script with the same shared helpers baked in.

| Tool | Command |
|---|---|
| All-in-one menu | `irm https://menu.geyer.zone \| iex` |
| AdwCleaner | `irm https://adwcleaner.geyer.zone \| iex` |
| Windows Update | `irm https://update.geyer.zone \| iex` |
| Software Setup | `irm https://redist.geyer.zone \| iex` |
| Inventory | `irm https://raw.githubusercontent.com/Bladeage/win-toolbox/main/dist/inventory.ps1 \| iex` |
| Clean Traces | `irm https://raw.githubusercontent.com/Bladeage/win-toolbox/main/dist/clean-traces.ps1 \| iex` |
| Install / repair WinGet | `irm https://raw.githubusercontent.com/Bladeage/win-toolbox/main/dist/winget.ps1 \| iex` |
| Harden System Security | `irm https://raw.githubusercontent.com/Bladeage/win-toolbox/main/dist/harden.ps1 \| iex` |

The short URLs redirect to the raw files in [`dist/`](dist/) on the `main` branch.

From a local copy you can start a tool directly: `.\dist\win-toolbox.ps1 -Tool update`
(`activate`, `update`, `winget`, `software`, `office`, `winutil`, `winscript`, `adwcleaner`,
`harden`, `inventory`, `traces`).

### Software Setup

Software Setup installs software with winget. Instead of parsing `winget search` output it
works from an explicit catalog (`catalog/software.json`). `build-catalog.ps1` generates it from
the *Runtimes* section maintained here plus the app list of
[ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil).

| Profile | Contents |
|---|---|
| Runtimes | Visual C++ 2005–2022 (x86+x64), VCLibs, .NET Desktop/Runtime 8 + 10, .NET Framework 3.5, DirectX, XNA, WebView2 |
| Standard | Runtimes + 7-Zip, Notepad++, Sumatra PDF, VLC, Firefox, ShareX, Everything, PowerToys, Windows Terminal, PowerShell 7 |
| Gaming | Standard + Java 21/25 (Temurin), Steam, TeamSpeak, Discord, HWiNFO, MSI Afterburner, CrystalDiskInfo, GPU-Z, CPU-Z, OBS, K-Lite, Parsec |
| Technician | Diagnostics, disks, drivers, uninstallers, network tools (WizTree, Autoruns, DDU, Rufus, Ventoy, Revo, PuTTY, WinSCP, gsudo, …) |

Profiles are additive. Afterwards you can browse every category and toggle single packages
(`1 4 7-9`, `a` all, `n` none, `i 3` info). `w` saves the selection to `Documents\win-toolbox\*.json`.
`l` loads a selection from a file or a URL, so the same set can be applied on every machine.

The install engine finds `winget.exe` even when an elevated shell lacks it in `PATH`, installs
WinGet when missing, runs every package with a timeout (kills the whole installer tree on
hang), tries machine scope → user scope → any source, retries with back-off, and verifies the
result by the real installation state rather than the exit code. Each run writes
`%TEMP%\win-toolbox\software-setup_<host>_<stamp>.log` + `.csv`.

### Inventory & Clean Traces (technician tools)

Two tools for field technicians, with English menus.

**Inventory** writes three CSV files: a long-format detail file per machine, plus an overview
and a software list that grow with every run. The column names are **German on purpose**, so
the files stay compatible with a companion Linux script and existing collections. Output goes
to the Desktop, the current directory, or a folder you pick. It runs without admin rights; some
fields need elevation.

**Clean Traces** clears the current user's shell history, Run/address-bar/Recent lists, temp
files and optionally the recycle bin. It runs as a **dry run by default**. `[m]` switches to
Execute after a confirmation. It never touches Windows event logs or USB device history.

## Troubleshooting

**"Running scripts is disabled on this system"**
`irm | iex` is not affected by the execution policy. The message appears when you run a
downloaded `.ps1` file. Start it like this:
`powershell -ExecutionPolicy Bypass -File .\win-toolbox.ps1`

**"Security Warning: Script Execution Risk"** (Windows PowerShell 5.1)
Windows shows this since the December 2025 updates when a script calls `Invoke-WebRequest`
without `-UseBasicParsing` ([KB5074596](https://support.microsoft.com/kb/5074596)).
win-toolbox always uses `-UseBasicParsing`. If the warning appears, it most likely comes from
a third-party tool started from the menu.

**Antivirus blocks the command**
Some antivirus products flag `irm | iex` one-liners or individual third-party tools.
Check *Windows Security → Protection history* to see what was blocked.

**Logs**
Tools that change the system write a log to `%TEMP%\win-toolbox\`.

Found a bug? [Open an issue](https://github.com/Bladeage/win-toolbox/issues/new/choose) and
include the exact message, your Windows version and the PowerShell version
(`$PSVersionTable.PSVersion`).

## How it is built

```
src/common.ps1          shared helpers: output, logging, admin check + self-elevation, downloads
src/winget.ps1          robust winget engine (path discovery, timeout, variants, retries, verification)
src/tools/*.ps1         one file per own tool (adwcleaner, windows-update, software, inventory, traces) + external wrappers
src/menu.ps1            text menu / grid picker
catalog/software.json   Software Setup catalog (generated by build-catalog.ps1, committed)
build.ps1               concatenates src/ (+ embeds the catalog) into the self-contained files in dist/
VERSION                 version string baked into dist/ (bump on release)
```

`dist/` is committed on purpose: the short URLs point straight at the raw files, so a merge to
`main` is a release. After editing `src/`, run `./build.ps1` (needs `pwsh`, works on
Linux/macOS/Windows) and commit the result.

CI lints `src/` with PSScriptAnalyzer (PS 5.1 + 7 syntax), rebuilds, parses `dist/` with both
PowerShell 7 and Windows PowerShell 5.1, fails if `dist/` is stale, and runs `tests/smoke.ps1`
on both: a scripted walk through the menu and every tool with winget, Start-Process,
PSWindowsUpdate and the UAC elevation mocked. Run it locally with `pwsh ./tests/smoke.ps1`.

Each dist file is wrapped in `& { ... }`, so running it via `irm | iex` leaves no functions,
variables or `$ErrorActionPreference` changes behind in your shell.

Changes are listed in the [changelog](CHANGELOG.md).

## Credits

win-toolbox merges and replaces several older scripts: Powershell-Menu,
Powershell-Windows-Update, AdwCleaner-Script and a fork of the PC-Gaming-Redists AIO batch
script by [harryeffinpotter](https://github.com/harryeffinpotter) and
[skrimix](https://github.com/skrimix). The Software Setup catalog builds on
[ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil).

## License

[MIT](LICENSE). Third-party scripts started from the menu keep their own licenses.
