#requires -Version 5.1
<#
.SYNOPSIS
    Smoke test for win-toolbox: drives the menu with scripted key presses and runs every
    tool against mocked Windows pieces (winget, Start-Process, PSWindowsUpdate, elevation).
    Runs on Linux/macOS pwsh as well as Windows PowerShell 5.1. Exit code 1 on any failure.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$ToolboxVersion = 'smoke'
$SelfUrl = 'https://example.invalid/win-toolbox.ps1'

# ---- load sources (same order as build.ps1) --------------------------------
foreach ($part in 'common', 'tools/adwcleaner', 'tools/windows-update', 'tools/redists', 'tools/external', 'menu') {
    . (Join-Path $root "src/$part.ps1")
}

# ---- tiny assertion helper --------------------------------------------------
$script:Pass = 0; $script:Fail = 0
function Assert {
    param([bool]$Condition, [string]$Name)
    if ($Condition) { $script:Pass++; Write-Host "  ok    $Name" -ForegroundColor Green }
    else            { $script:Fail++; Write-Host "  FAIL  $Name" -ForegroundColor Red }
}

# ---- mocks ------------------------------------------------------------------
$script:Calls = @{}
function Record { param([string]$What, $Detail) if (-not $script:Calls.ContainsKey($What)) { $script:Calls[$What] = @() }; $script:Calls[$What] += ,$Detail }
function Reset-Calls { $script:Calls = @{}; $script:KeyQueue = @(); $script:Admin = $true; $script:WingetPresent = $true }
function Get-Calls { param([string]$What) if ($script:Calls.ContainsKey($What)) { return ,@($script:Calls[$What]) } else { return ,@() } }

function Test-IsAdmin { return $script:Admin }
function Clear-Host { }
function Wait-AnyKey { param([string]$Prompt) Record 'Wait-AnyKey' $Prompt }
function Read-MenuKey {
    if ($script:KeyQueue.Count -eq 0) { throw 'Read-MenuKey: key queue exhausted - menu did not exit' }
    $k = $script:KeyQueue[0]; $script:KeyQueue = @($script:KeyQueue | Select-Object -Skip 1); return $k
}
function Out-GridView { param([Parameter(ValueFromPipeline)]$InputObject, $Title, $OutputMode) process { Record 'Out-GridView' $InputObject } end { return $null } }
function Start-Process { param($FilePath, $ArgumentList, [switch]$Wait, $Verb, $ErrorAction) Record 'Start-Process' @{ FilePath = $FilePath; Args = $ArgumentList; Verb = $Verb } }
function Get-RemoteFile { param($Uri, $OutFile, $Retries) Record 'Get-RemoteFile' $Uri; Set-Content -Path $OutFile -Value 'dummy' }
function Invoke-RemoteScript { param($Url, $Name) Record 'Invoke-RemoteScript' $Url }
function Update-SessionPath { }
function Get-StartApps { @() }
function winget {
    param([Parameter(ValueFromRemainingArguments)]$a)
    if ($a[0] -eq '--version') { return 'v9.9-mock' }
    Record 'winget' ($a -join ' ')
    $id = $a[$a.IndexOf('--id') + 1]
    $global:LASTEXITCODE = switch ($id) {
        'Microsoft.DirectX' { -1978335189 }   # already installed
        '7zip.7zip'         { -1978335212 }   # not found
        default             { 0 }
    }
    return 'mock winget output'
}
function Test-Command { param($Name) if ($Name -eq 'winget') { return $script:WingetPresent } ; return $true }
function Get-WindowsOptionalFeature { param([switch]$Online, $FeatureName) Record 'Get-WindowsOptionalFeature' $FeatureName; [pscustomobject]@{ State = 'Disabled' } }
function Enable-WindowsOptionalFeature { param([switch]$Online, $FeatureName, [switch]$All, [switch]$NoRestart) Record 'Enable-WindowsOptionalFeature' $FeatureName }
function Get-PackageProvider { param($Name, [switch]$ListAvailable) return $null }
function Install-PackageProvider { param($Name, $MinimumVersion, [switch]$Force) Record 'Install-PackageProvider' $Name }
function Get-Module { param($Name, [switch]$ListAvailable) return $null }
function Install-Module { param($Name, [switch]$Force) Record 'Install-Module' $Name }
function Import-Module { param($Name) Record 'Import-Module' $Name }
function Get-WindowsUpdate {
    param([switch]$Install, [switch]$AcceptAll, [switch]$AutoReboot, [switch]$IgnoreReboot)
    Record 'Get-WindowsUpdate' @{ Install = $Install.IsPresent; AcceptAll = $AcceptAll.IsPresent; AutoReboot = $AutoReboot.IsPresent; IgnoreReboot = $IgnoreReboot.IsPresent }
    return @([pscustomobject]@{ KB = 'KB1'; Size = '1MB'; Title = 'Mock update' })
}

# ---- scenarios --------------------------------------------------------------
Write-Host "`n[1] menu table"
Assert ($MenuItems.Count -eq 9) 'menu has 9 items'
Assert ((@($MenuItems | ForEach-Object Key | Sort-Object -Unique)).Count -eq 9) 'keys are unique'
Assert ((@($MenuItems | ForEach-Object Id | Sort-Object -Unique)).Count -eq 9) 'ids are unique'

Write-Host "`n[2] AdwCleaner via menu key 8, then quit"
Reset-Calls; $script:KeyQueue = @('8', 'q')
Show-Menu 6>$null
Assert ((Get-Calls 'Get-RemoteFile') -contains $Urls.AdwCleaner) 'downloads AdwCleaner URL'
Assert ((Get-Calls 'Start-Process').Count -eq 1) 'starts adwcleaner.exe once'
Assert (-not (Test-Path (Join-Path ([IO.Path]::GetTempPath()) 'adwcleaner.exe'))) 'temp exe removed afterwards'
Assert ((Get-Calls 'Wait-AnyKey').Count -eq 1) 'returns to menu once'

Write-Host "`n[3] external irm|iex wrappers (keys 1,5,6,7)"
Reset-Calls; $script:KeyQueue = @('1', '5', '6', '7', 'q')
Show-Menu 6>$null
$remote = Get-Calls 'Invoke-RemoteScript'
Assert ($remote -contains $Urls.MAS) 'MAS URL'
Assert ($remote -contains $Urls.OfficeToolPlus) 'Office Tool Plus URL'
Assert ($remote -contains $Urls.WinUtil) 'WinUtil URL'
Assert ($remote -contains $Urls.WinScript) 'WinScript URL'
Assert ($remote.Count -eq 4) 'exactly 4 remote scripts'

Write-Host "`n[4] gaming redists via key 4 (mock winget, NetFx3)"
Reset-Calls; $script:KeyQueue = @('4', 'q')
Show-Menu 6>$null
$w = Get-Calls 'winget'
Assert ($w.Count -eq $RedistPackages.Count) "winget called once per package ($($w.Count)/$($RedistPackages.Count))"
Assert (($w | Where-Object { $_ -notmatch '--silent' }).Count -eq 0) 'every call is --silent'
Assert (($w | Where-Object { $_ -match '--force' }).Count -eq 0) 'no --force by default'
Assert ((Get-Calls 'Enable-WindowsOptionalFeature') -contains 'NetFx3') 'enables NetFx3'

Write-Host "`n[5] redists -Force and -Group directly"
Reset-Calls
Install-GamingRedists -Group 'Java' -Force 6>$null
$w = Get-Calls 'winget'
Assert ($w.Count -eq 2) 'Java group = 2 packages'
Assert (($w | Where-Object { $_ -notmatch '--force' }).Count -eq 0) '-Force passes --force'
Assert ((Get-Calls 'Enable-WindowsOptionalFeature').Count -eq 0) 'NetFx3 skipped when .NET group not selected'

Write-Host "`n[6] Install-WinGetPackage exit-code mapping"
Reset-Calls
Assert ((Install-WinGetPackage -Id 'Microsoft.VCRedist.2015+.x64' 6>$null) -eq $true) 'exit 0 -> true'
Assert ((Install-WinGetPackage -Id 'Microsoft.DirectX' 6>$null) -eq $true) 'already installed -> true'
Assert ((Install-WinGetPackage -Id '7zip.7zip' 6>$null) -eq $false) 'not found -> false'

Write-Host "`n[7] WinGet install path when winget is missing"
Reset-Calls; $script:WingetPresent = $false
try { Install-GamingRedists -Group 'Tools' 6>$null } catch { Record 'Error' $_.Exception.Message }
Assert ((Get-Calls 'Invoke-RemoteScript') -contains $Urls.WinGetInstall) 'falls back to winget-install script'
Assert ((Get-Calls 'Error').Count -eq 1) 'throws clearly when winget still missing'

Write-Host "`n[8] Windows Update via -Tool update"
Reset-Calls
Show-Menu -Tool update 6>$null
$u = Get-Calls 'Get-WindowsUpdate'
Assert ($u.Count -eq 2) 'search + install'
Assert ($u[1].Install -and $u[1].AcceptAll -and $u[1].AutoReboot) 'installs with -AcceptAll -AutoReboot'
Assert ((Get-Calls 'Install-Module') -contains 'PSWindowsUpdate') 'installs PSWindowsUpdate when missing'
Reset-Calls
Invoke-WindowsUpdate -NoReboot 6>$null
Assert ((Get-Calls 'Get-WindowsUpdate')[1].IgnoreReboot) '-NoReboot -> -IgnoreReboot'

Write-Host "`n[9] Harden System Security"
Reset-Calls; $script:KeyQueue = @('9', 'q')
Show-Menu 6>$null
$w = Get-Calls 'winget'
if ([Environment]::OSVersion.Version.Build -ge 22621) {
    Assert ($w.Count -eq 1 -and $w[0] -match '9p7ggfl7dx57' -and $w[0] -match '--source msstore') 'installs store app via msstore'
} else {
    Assert ($w.Count -eq 0) 'refuses on builds below Win 11 22H2 (this host)'
}

Write-Host "`n[10] menu edge cases"
Reset-Calls; $script:KeyQueue = @('x', 'Q')
Show-Menu 6>$null
Assert ((Get-Calls 'Wait-AnyKey').Count -eq 0) 'unknown key does not run a tool'
Reset-Calls; $script:KeyQueue = @('G', 'q')       # grid -> mocked Out-GridView cancels -> back to text
Show-Menu 6>$null
Assert ((Get-Calls 'Out-GridView').Count -eq 9) 'grid view receives all 9 rows'
Reset-Calls
Show-Menu -Tool nope 6>$null
Assert ((Get-Calls 'Wait-AnyKey').Count -eq 0) '-Tool with unknown id is rejected'
Reset-Calls
Show-Menu -Tool adwcleaner 6>$null
Assert ((Get-Calls 'Start-Process').Count -eq 1) '-Tool adwcleaner runs directly'

Write-Host "`n[11] elevation"
Reset-Calls; $script:Admin = $false
$started = Invoke-Elevated -SelfUrl $SelfUrl -Arguments '-Tool update' 6>$null
$sp = Get-Calls 'Start-Process'
Assert ($started -eq $true) 'reports that an elevated process was started'
Assert ($sp.Count -eq 1 -and $sp[0].Verb -eq 'RunAs') 'uses -Verb RunAs'
Assert (($sp[0].Args -join ' ') -match '-ExecutionPolicy Bypass') 'bypasses execution policy'
Assert (($sp[0].Args -join ' ') -match "irm 'https://example.invalid/win-toolbox.ps1' \| iex|common\.ps1' -Tool update") 're-runs via irm|iex (or the file when run from disk)'
$script:Admin = $true
Assert ((Invoke-Elevated -SelfUrl $SelfUrl 6>$null) -eq $false) 'no-op when already admin'

Write-Host "`n[12] tool functions throw (not exit) without admin"
Reset-Calls; $script:Admin = $false
$thrown = 0
foreach ($fn in 'Invoke-WindowsUpdate', 'Install-GamingRedists') { try { & $fn 6>$null } catch { $thrown++ } }
Assert ($thrown -eq 2) 'update + redists refuse without admin'
$script:Admin = $true

Write-Host "`n[13] dist files"
foreach ($f in Get-ChildItem (Join-Path $root 'dist') -Filter *.ps1) {
    $text = Get-Content $f.FullName -Raw
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
    Assert ($errors.Count -eq 0) "$($f.Name) parses"
    Assert ($text -match "`r`n" -and $text -notmatch "[^`r]`n") "$($f.Name) is CRLF"
    Assert ($text -match '(?m)^& \{\r?$' -and $text.TrimEnd().EndsWith('}')) "$($f.Name) is wrapped in & { }"
    Assert ($text -match '\$SelfUrl = ''https://raw\.githubusercontent\.com/Bladeage/win-toolbox/main/dist/') "$($f.Name) has SelfUrl baked in"
    Assert ($text -notmatch '[^\x00-\x7F]') "$($f.Name) is ASCII-only"
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:Pass, $script:Fail) -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
if ($script:Fail) { exit 1 } else { exit 0 }   # explicit: mocks leave $LASTEXITCODE non-zero, CI pwsh shell would propagate it
