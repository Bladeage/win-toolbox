# win-toolbox — Projekt-CLAUDE.md

PowerShell-Skripte für Windows, ausgeliefert als `irm <url> | iex`-Einzeiler. Quelle ist
**GitHub `Bladeage/win-toolbox` (öffentlich, secret-frei)**; `git.geyer.zone` spiegelt nur.
Betriebsmodus: **Ship-Loop** (PR-Flow, CI grün, Merge → Raw-URLs sind sofort live).

## Aufbau
- `src/common.ps1` — gemeinsame Helfer (Output, Log, Admin/Elevation, Download). **PS-5.1-kompatibel halten**
  (kein Ternary, kein `??`, keine Klassen). `$Urls` ist die einzige Stelle für Fremd-URLs.
- `src/winget.ps1` — robuste winget-Engine (Port aus `Install-Software.ps1` vom Techniker-Stick): winget.exe-Suche,
  Timeout+taskkill, Scope-Varianten, Retries, Verifikation per `winget list`. Nur in toolbox/software-setup eingebaut.
- `src/tools/*.ps1` — je Tool eine Funktion. `external.ps1` = dünne `irm|iex`-Wrapper für Fremdskripte.
  `software.ps1` = Software Setup (Profile/Katalog/Suche/Auswahl speichern+laden/Dry-Run).
  `inventory.ps1` = Inventar (englische UI, **CSV-Schema bleibt deutsch** — kompatibel zu inventar-linux.sh; Ausgabeort
  Desktop/CWD/FolderBrowserDialog). `traces.ps1` = Spuren entfernen (Dry-Run-Default, `[m]` → Execute mit Rückfrage).
- Eingabe-Nähte für Tests: `Read-MenuKey` (Einzeltaste, in menu.ps1) und `Read-MenuLine` (Zeile, in common.ps1) —
  tests/smoke.ps1 ersetzt beide. Logging heißt `Write-LogLine` (nicht Write-Log, das ist ein PS-Cmdlet).
- `catalog/software.json` — **generiert** durch `build-catalog.ps1` (Runtimes-Sektion + Profile dort gepflegt, Rest aus
  winutil `applications.json`), ASCII-only (EscapeNonAscii), committet. `build.ps1` bettet es als `$CatalogJson`-Here-String ein.
- Funktionen, die Collections zurückgeben: `return ,$x` (sonst entrollt PowerShell — HashSet-Falle ist schon passiert).
- `src/menu.ps1` — `$MenuItems` (Key/Id/Name/Description/Action) + Text-/Grid-Menü.
- `build.ps1` → `dist/*.ps1` (committet!). Jede dist-Datei: Header + `& { common + tools + entry }`,
  `$SelfUrl` eingebacken für die Selbst-Elevation per `irm|iex`. CRLF, ASCII-only (Build bricht bei Nicht-ASCII ab, kein BOM).
- `VERSION` — bei Release bumpen; landet im Banner/Header.

## Workflow
1. `src/` ändern → `./build.ps1` (lokal `pwsh` 7.6 vorhanden) → `dist/` mitcommitten.
2. Lint lokal: `Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1`
   (PSScriptAnalyzer ist im User-Scope installiert).
3. `pwsh ./tests/smoke.ps1` — Rauchtest: fährt das Menü mit Tasten-Queue durch, alle Tools mit gemocktem
   winget/Start-Process/PSWindowsUpdate/Elevation (`Read-MenuKey` ist die Test-Naht). Läuft in CI auf Ubuntu
   **und** echtem PS 5.1. Fabian arbeitet auf Linux — **dieser Test ist der Rauchtest**, es gibt keine Windows-Kiste.
4. Branch → PR → CI (lint, build, parse PS 7 + 5.1, dist-aktuell-Check, smoke ×2) → Merge.
5. Nicht durch Mocks abgedeckt (Restrisiko): echtes winget-Verhalten, UAC-Dialog, Out-GridView-Optik,
   Verhalten der Fremdskripte (MAS, WinUtil, …).

## Auslieferung
- Kurz-URLs `menu.` / `adwcleaner.` / `update.` / `redist.geyer.zone` (redist → `dist/software-setup.ps1`) (+ `activate.`/`office.`/`winutil.`/`winscript.`
  direkt auf Upstream) sind **301-Redirection-Hosts im Nginx Proxy Manager auf `hp`** (Cloudflare nur davor;
  Ändern = NPM-UI oder -API auf hp, SSH braucht FIDO-Touch → Fabian) → Ziel:
  `https://raw.githubusercontent.com/Bladeage/win-toolbox/main/dist/<datei>`.
- Merge auf `main` = Deploy. Kein weiterer Schritt. Deshalb: nie direkt auf `main` committen.

## Herkunft
Powershell-Menu, Powershell-Windows-Update, AdwCleaner-Script (Gitea) und der GitHub-Fork
`Bladeage/PC-Gaming-Redists` (Batch-AIO von harryeffinpotter/skrimix) sind hier aufgegangen.
`winscript` auf Gitea ist ein reiner Upstream-Mirror (flick9000) — kein eigener Code.
**Techniker-Stick** (`~/Downloads/stick/`, Heimat teils `arbeitsplatz-werkzeuge`, privat): `Software-Setup/` ist hier
als Software Setup (Englisch) aufgegangen; `Inventarisierung/` und `Spuren-Entfernen/` folgen als Menüpunkte
(Fabians Entscheidung 2026-08-20: alles ins Menü, erstmal Englisch, kein Stick-Launcher).
