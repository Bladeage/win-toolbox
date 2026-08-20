#requires -Version 7.0
<#
.SYNOPSIS
    Generates catalog/software.json (English) for the Software Setup tool.
.DESCRIPTION
    Sources:
      - Runtimes section + profiles: maintained here (IDs verified against microsoft/winget-pkgs)
      - Everything else: ChrisTitusTech/winutil config/applications.json
    Run manually when you want to refresh the catalog, then commit the result:
        pwsh ./build-catalog.ps1
    Needs PowerShell 7 for ConvertTo-Json -EscapeHandling (keeps the catalog ASCII-only).
#>
[CmdletBinding()]
param(
    [string]$WinutilJson,   # optional local copy of applications.json (default: download)
    [string]$OutFile = (Join-Path $PSScriptRoot 'catalog/software.json')
)
$ErrorActionPreference = 'Stop'
$winutilUrl = 'https://raw.githubusercontent.com/ChrisTitusTech/winutil/main/config/applications.json'

$categoryMap = [ordered]@{
    'Utilities'        = 'Utilities'
    'Browsers'         = 'Browsers'
    'Document'         = 'Documents'
    'Multimedia Tools' = 'Multimedia'
    'Communications'   = 'Communication'
    'Microsoft Tools'  = 'Microsoft Tools'
    'Pro Tools'        = 'Network & Pro Tools'
    'Games'            = 'Games'
    'Development'      = 'Development'
    'Selfhosted Tools' = 'Self-hosted'
}
$categoryOrder = @('Runtimes') + @($categoryMap.Values)

# key, name, winget id, info
$runtimes = @(
    @('vcredist2005x86', 'Visual C++ 2005 (x86)',      'Microsoft.VCRedist.2005.x86', 'Runtime for older applications and games.'),
    @('vcredist2005x64', 'Visual C++ 2005 (x64)',      'Microsoft.VCRedist.2005.x64', 'Runtime for older applications and games.'),
    @('vcredist2008x86', 'Visual C++ 2008 (x86)',      'Microsoft.VCRedist.2008.x86', 'Runtime for older applications and games.'),
    @('vcredist2008x64', 'Visual C++ 2008 (x64)',      'Microsoft.VCRedist.2008.x64', 'Runtime for older applications and games.'),
    @('vcredist2010x86', 'Visual C++ 2010 (x86)',      'Microsoft.VCRedist.2010.x86', 'Runtime for older applications and games.'),
    @('vcredist2010x64', 'Visual C++ 2010 (x64)',      'Microsoft.VCRedist.2010.x64', 'Runtime for older applications and games.'),
    @('vcredist2012x86', 'Visual C++ 2012 (x86)',      'Microsoft.VCRedist.2012.x86', 'Runtime for older applications and games.'),
    @('vcredist2012x64', 'Visual C++ 2012 (x64)',      'Microsoft.VCRedist.2012.x64', 'Runtime for older applications and games.'),
    @('vcredist2013x86', 'Visual C++ 2013 (x86)',      'Microsoft.VCRedist.2013.x86', 'Runtime for older applications and games.'),
    @('vcredist2013x64', 'Visual C++ 2013 (x64)',      'Microsoft.VCRedist.2013.x64', 'Runtime for older applications and games.'),
    @('vcredist2015x86', 'Visual C++ 2015-2022 (x86)', 'Microsoft.VCRedist.2015+.x86', 'Current Visual C++ runtime, 32-bit. Needed by a huge number of programs.'),
    @('vcredist2015x64', 'Visual C++ 2015-2022 (x64)', 'Microsoft.VCRedist.2015+.x64', 'Current Visual C++ runtime, 64-bit. Needed by a huge number of programs.'),
    @('vclibs14',        'VCLibs Desktop 14',          'Microsoft.VCLibs.Desktop.14',  'Visual C++ libraries for packaged (Store / Game Pass) apps.'),
    @('directx',         'DirectX End-User Runtime',   'Microsoft.DirectX',            'Legacy DirectX components (d3dx9, XAudio2, XInput) - needed by many older games.'),
    @('xna',             'XNA Framework Redistributable', 'Microsoft.XNARedist',       'Runtime for games built on the XNA Framework.'),
    @('webview2',        'Edge WebView2 Runtime',      'Microsoft.EdgeWebView2Runtime', 'Runtime for applications with an embedded browser view.'),
    @('dotnetdesktop8',  '.NET Desktop Runtime 8 (LTS)',  'Microsoft.DotNet.DesktopRuntime.8',  'LTS runtime for .NET desktop apps (WPF/WinForms).'),
    @('dotnetdesktop10', '.NET Desktop Runtime 10 (LTS)', 'Microsoft.DotNet.DesktopRuntime.10', 'Current LTS runtime for .NET desktop apps (WPF/WinForms).'),
    @('dotnetruntime8',  '.NET Runtime 8 (LTS)',       'Microsoft.DotNet.Runtime.8',   'LTS base runtime for .NET console and server apps.'),
    @('dotnetruntime10', '.NET Runtime 10 (LTS)',      'Microsoft.DotNet.Runtime.10',  'Current LTS base runtime for .NET console and server apps.'),
    @('dotnetdesktop6',  '.NET Desktop Runtime 6 (EOL)',  'Microsoft.DotNet.DesktopRuntime.6',  'Out of support - only install if a legacy app requires it.'),
    @('dotnetdesktop7',  '.NET Desktop Runtime 7 (EOL)',  'Microsoft.DotNet.DesktopRuntime.7',  'Out of support - only install if a legacy app requires it.'),
    @('dotnetdesktop9',  '.NET Desktop Runtime 9 (EOL)',  'Microsoft.DotNet.DesktopRuntime.9',  'Out of support - only install if a legacy app requires it.'),
    @('temurin8jre',     'Java 8 JRE (Temurin)',       'EclipseAdoptium.Temurin.8.JRE',  'Free Java 8 runtime for old Java apps and games (replaces Oracle JRE 8).'),
    @('temurin21jre',    'Java 21 JRE (Temurin, LTS)', 'EclipseAdoptium.Temurin.21.JRE', 'Free Java runtime, LTS. Covers most Java applications.'),
    @('temurin25jre',    'Java 25 JRE (Temurin, LTS)', 'EclipseAdoptium.Temurin.25.JRE', 'Free Java runtime, current LTS.')
)
$features = @(
    [ordered]@{ key = 'netfx35'; name = '.NET Framework 3.5 (Windows feature)'; category = 'Runtimes'; type = 'feature'; id = ''; feature = 'NetFx3'
                info = 'Needed by older applications. Enabled via DISM, downloads files from Windows Update.'; foss = $false
                link = 'https://learn.microsoft.com/dotnet/framework/install/dotnet-35-windows' }
)
$profiles = [ordered]@{
    Runtimes   = @{ description = 'Runtimes and redistributables only - the baseline for every PC.'
                    apps = @('vcredist2005x86','vcredist2005x64','vcredist2008x86','vcredist2008x64','vcredist2010x86','vcredist2010x64',
                             'vcredist2012x86','vcredist2012x64','vcredist2013x86','vcredist2013x64','vcredist2015x86','vcredist2015x64',
                             'vclibs14','directx','xna','webview2','dotnetdesktop8','dotnetdesktop10','dotnetruntime8','dotnetruntime10','netfx35') }
    Standard   = @{ description = 'Runtimes plus a uniform basic toolset for every PC.'
                    apps = @('__Runtimes__','7zip','notepadplus','sumatra','vlc','firefox','sharex','everything','powertoys','terminal','powershell') }
    Gaming     = @{ description = 'Standard plus everything a gaming / simulation PC needs.'
                    apps = @('__Standard__','temurin21jre','temurin25jre','steam','teamspeak3','discord','hwinfo','msiafterburner',
                             'crystaldiskinfo','gpuz','cpuz','obs','klite','parsec') }
    Technician = @{ description = 'Maintenance, diagnostics and reinstall toolkit.'
                    apps = @('7zip','notepadplus','everything','wiztree','treesize','hwinfo','crystaldiskinfo','crystaldiskmark','cpuz','gpuz',
                             'autoruns','processexplorer','ddu','sdio','rufus','ventoy','revo','bulkcrapuninstaller','advancedip','putty',
                             'winscp','gsudo','totalcommander') }
}

# ---- load winutil --------------------------------------------------------------
if ($WinutilJson) { $raw = Get-Content -LiteralPath $WinutilJson -Raw }
else { Write-Host "downloading $winutilUrl"; $raw = (Invoke-WebRequest -Uri $winutilUrl -UseBasicParsing).Content }
$upstream = $raw | ConvertFrom-Json -AsHashtable

$apps = [System.Collections.Generic.List[object]]::new()
$usedIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($r in $runtimes) {
    $apps.Add([ordered]@{ key = $r[0]; name = $r[1]; category = 'Runtimes'; type = 'winget'; id = $r[2]; info = $r[3]; foss = $false; link = 'https://learn.microsoft.com/' })
    [void]$usedIds.Add($r[2])
}
foreach ($f in $features) { $apps.Add($f) }

$skipped = @()
foreach ($entry in ($upstream.GetEnumerator() | Sort-Object { $_.Value.content.ToLower() })) {
    $v = $entry.Value
    $id = [string]$v.winget
    if (-not $id -or $id -eq 'na') { $skipped += "$($entry.Key) (no winget id)"; continue }
    if (-not $usedIds.Add($id)) { $skipped += "$($entry.Key) (duplicate of runtimes: $id)"; continue }
    $cat = if ($categoryMap.Contains($v.category)) { $categoryMap[$v.category] } else { $v.category }
    $apps.Add([ordered]@{
        key = $entry.Key; name = [string]$v.content; category = $cat; type = 'winget'; id = $id
        info = ([string]$v.description).Trim(); foss = [bool]$v.foss; link = [string]$v.link
    })
}

# ---- resolve profiles (__Name__ embeds another profile) -------------------------
$known = [System.Collections.Generic.HashSet[string]]::new([string[]]($apps | ForEach-Object key), [StringComparer]::OrdinalIgnoreCase)
function Resolve-Profile([string]$Name, [int]$Depth = 0) {
    if ($Depth -gt 5) { throw 'profile nesting too deep' }
    $out = @()
    foreach ($e in $profiles[$Name].apps) {
        if ($e -match '^__(.+)__$') { $out += Resolve-Profile $Matches[1] ($Depth + 1) }
        elseif (-not $known.Contains($e)) { throw "profile $Name references unknown app key '$e'" }
        else { $out += $e }
    }
    return $out
}
$resolved = [ordered]@{}
foreach ($p in $profiles.Keys) {
    $resolved[$p] = [ordered]@{ description = $profiles[$p].description; apps = @(Resolve-Profile $p | Select-Object -Unique) }
}

$catalog = [ordered]@{
    schema     = 1
    updated    = (Get-Date -Format 'yyyy-MM-dd')
    source     = 'Runtimes: maintained in build-catalog.ps1 (IDs verified against microsoft/winget-pkgs). Other packages: ChrisTitusTech/winutil config/applications.json.'
    categories = $categoryOrder
    profiles   = $resolved
    apps       = $apps
}
$json = $catalog | ConvertTo-Json -Depth 6 -EscapeHandling EscapeNonAscii
$json = ($json -replace "`r`n", "`n") + "`n"
New-Item -ItemType Directory -Path (Split-Path $OutFile) -Force | Out-Null
[IO.File]::WriteAllText($OutFile, $json, (New-Object Text.UTF8Encoding $false))

Write-Host ("{0} packages written to {1}" -f $apps.Count, $OutFile)
$apps | Group-Object { $_.category } | ForEach-Object { Write-Host ("  {0,-22} {1,3}" -f $_.Name, $_.Count) }
foreach ($p in $resolved.Keys) { Write-Host ("  profile {0,-11} {1,3} packages" -f $p, $resolved[$p].apps.Count) }
if ($skipped) { Write-Host "skipped: $($skipped -join ', ')" }
