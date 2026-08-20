# win-toolbox

One-liner Windows helper scripts, bundled into a single `irm | iex` menu.

```powershell
irm https://menu.geyer.zone | iex
```

| Key | Tool | What it does |
|---|---|---|
| 1 | Activate Windows / Office | [Microsoft Activation Scripts](https://massgrave.dev) |
| 2 | Windows Update | Installs every pending update via [PSWindowsUpdate](https://www.powershellgallery.com/packages/PSWindowsUpdate) (auto-reboot) |
| 3 | Install / repair WinGet | [winget-install](https://github.com/asheroto/winget-install) by asheroto |
| 4 | Gaming redistributables | All VC++ runtimes, .NET desktop runtimes, .NET Framework 3.5, DirectX, XNA, 7zip, PowerShell 7, Windows Terminal, Java — via winget |
| 5 | Office Tool Plus | [officetool.plus](https://officetool.plus) |
| 6 | WinUtil | [Chris Titus Tech's Windows Utility](https://christitus.com/win) |
| 7 | WinScript | [flick9000/winscript](https://github.com/flick9000/winscript) |
| 8 | AdwCleaner | Downloads, runs and removes [Malwarebytes AdwCleaner](https://www.malwarebytes.com/adwcleaner) |
| 9 | Harden System Security | [HotCakeX's hardening app](https://github.com/HotCakeX/Harden-Windows-Security/wiki/Harden-System-Security) from the Microsoft Store (Windows 11 22H2+) |

`G` switches to an `Out-GridView` picker, `Q`/`Esc` quits. The menu asks for elevation (UAC) when
needed and re-launches itself. Works in Windows PowerShell 5.1 and PowerShell 7.

## Single tools

Every tool is also published as a standalone script with the same shared helpers baked in:

| Script | Short URL | Raw |
|---|---|---|
| All-in-one menu | `irm https://menu.geyer.zone \| iex` | `dist/win-toolbox.ps1` |
| AdwCleaner | `irm https://adwcleaner.geyer.zone \| iex` | `dist/adwcleaner.ps1` |
| Windows Update | `irm https://update.geyer.zone \| iex` | `dist/windows-update.ps1` |
| Gaming redists | `irm https://redist.geyer.zone \| iex` | `dist/redists.ps1` |

From a local checkout you can also run a tool directly: `.\dist\win-toolbox.ps1 -Tool update`
(`activate`, `update`, `winget`, `redists`, `office`, `winutil`, `winscript`, `adwcleaner`, `harden`).
`Install-GamingRedists -Force` reinstalls everything (winget `--force`), `-Group 'Visual C++','.NET'` limits the set.

## How it is built

```
src/common.ps1          shared helpers: output, admin check + self-elevation, downloads, winget
src/tools/*.ps1         one file per own tool (adwcleaner, windows-update, redists) + external wrappers
src/menu.ps1            text menu / grid picker
build.ps1               concatenates src/ into the self-contained files in dist/
VERSION                 version string baked into dist/ (bump on release)
```

`dist/` is committed on purpose — the short URLs (Nginx Proxy Manager 301 redirects) point straight at the raw files. After editing
`src/`, run `./build.ps1` (needs `pwsh`, works on Linux/macOS/Windows) and commit the result.
CI lints `src/` with PSScriptAnalyzer (PS 5.1 + 7 syntax), rebuilds, parses `dist/` with both
PowerShell 7 and Windows PowerShell 5.1, and fails if `dist/` is stale.

Each dist file is wrapped in `& { ... }`, so running it via `irm | iex` leaves no functions,
variables or `$ErrorActionPreference` changes behind in your shell.

## History

Merges and replaces these repositories: Powershell-Menu, Powershell-Windows-Update,
AdwCleaner-Script and the PC-Gaming-Redists fork (original AIO batch script by
[harryeffinpotter](https://github.com/harryeffinpotter) & [skrimix](https://github.com/skrimix)).

## License

MIT — third-party scripts invoked by the menu keep their own licenses.
