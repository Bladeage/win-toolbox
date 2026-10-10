# Security policy

## Supported versions

Only the current state of the `main` branch is supported. The short URLs always serve it.

## Reporting a vulnerability

Please do not report security problems in a public issue.

Use GitHub's private reporting instead:
[Report a vulnerability](https://github.com/Bladeage/win-toolbox/security/advisories/new).

Please include:
- the affected script and tool
- what an attacker can do
- steps to reproduce

## Scope

In scope: the scripts in `src/` and `dist/`, the build and the CI workflow.

Out of scope: third-party tools started from the menu (Microsoft Activation Scripts,
winget-install, Office Tool Plus, WinUtil, WinScript, Harden System Security, AdwCleaner,
PSWindowsUpdate). Please report problems in those to their own projects.
