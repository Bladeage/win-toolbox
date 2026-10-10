# Changelog

All notable changes to win-toolbox. The version is shown in the menu banner.
A merge to `main` is a release, because the short URLs point at the files in `dist/`.

## 1.0.1 (2026-10-10)

### Fixed
- Windows Update: relax the execution policy for the current PowerShell process only before
  loading PSWindowsUpdate. Without this, an admin shell opened directly (default policy
  `Restricted`) could fail to load the module.

### Changed
- README: safety notes, requirements, troubleshooting, full commands for every standalone tool.
- Added changelog, security policy and issue templates.

## 1.0.0 (2026-08-20)

First release of the combined toolbox.

- All-in-one menu (text menu and `Out-GridView` picker) with self-elevation via UAC.
- Own tools: Windows Update (PSWindowsUpdate), Software Setup (winget profiles and catalog),
  AdwCleaner, Inventory (CSV), Clean Traces (dry run by default).
- Wrappers for third-party tools: Microsoft Activation Scripts, winget-install,
  Office Tool Plus, WinUtil, WinScript, Harden System Security.
- Standalone scripts for every own tool in `dist/`.
