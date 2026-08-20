#requires -Version 5.1
<#
.SYNOPSIS
    Smoke test for win-toolbox: drives the menus with scripted input and runs every tool
    against mocked Windows pieces (winget process calls, Start-Process, PSWindowsUpdate,
    Windows features, UAC elevation). Runs on Linux/macOS pwsh and Windows PowerShell 5.1.
    Exit code 1 on any failure.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$ToolboxVersion = 'smoke'
$SelfUrl = 'https://example.invalid/win-toolbox.ps1'

# ---- load sources (same order as build.ps1) --------------------------------
foreach ($part in 'common', 'winget', 'tools/adwcleaner', 'tools/windows-update', 'tools/software', 'tools/inventory', 'tools/traces', 'tools/external', 'menu') {
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
function Get-Calls { param([string]$What) if ($script:Calls.ContainsKey($What)) { return ,@($script:Calls[$What]) } else { return ,@() } }
function Reset-Calls {
    $script:Calls = @{}; $script:KeyQueue = @(); $script:LineQueue = @()
    $script:Admin = $true; $script:WingetPath = 'C:\fake\winget.exe'
    $script:Installed = @{ 'Present.Pkg' = $true }
    $WinGetState.Ready = $false; $WinGetState.Path = $null
    $SoftwareState.Selected = $null; $SoftwareState.Upgrade = $false; $SoftwareState.DryRun = $false
}

function Test-IsAdmin { return $script:Admin }
function Clear-Host { }
function Wait-AnyKey { param([string]$Prompt) Record 'Wait-AnyKey' $Prompt }
function Read-MenuKey {
    if ($script:KeyQueue.Count -eq 0) { throw 'Read-MenuKey: key queue exhausted - menu did not exit' }
    $k = $script:KeyQueue[0]; $script:KeyQueue = @($script:KeyQueue | Select-Object -Skip 1); return $k
}
function Read-MenuLine {
    param([string]$Prompt)
    if ($script:LineQueue.Count -eq 0) { throw "Read-MenuLine: line queue exhausted at prompt '$Prompt'" }
    $l = $script:LineQueue[0]; $script:LineQueue = @($script:LineQueue | Select-Object -Skip 1); return $l
}
function Out-GridView { param([Parameter(ValueFromPipeline)]$InputObject, $Title, $OutputMode) process { Record 'Out-GridView' $InputObject } end { return $null } }
function Start-Process { param($FilePath, $ArgumentList, [switch]$Wait, $Verb, $ErrorAction) Record 'Start-Process' @{ FilePath = $FilePath; Args = $ArgumentList; Verb = $Verb } }
function Get-RemoteFile { param($Uri, $OutFile, $Retries) Record 'Get-RemoteFile' $Uri; Set-Content -Path $OutFile -Value 'dummy' }
function Invoke-RemoteScript { param($Url, $Name) Record 'Invoke-RemoteScript' $Url }
function Update-SessionPath { }
function Get-StartApps { @() }
function Get-WinGetPath { return $script:WingetPath }
function Invoke-Process {
    # fake winget: remembers what got installed, fails for Fail.Pkg
    param($FilePath, [string[]]$ArgumentList, $TimeoutSeconds)
    $a = $ArgumentList -join ' '
    Record 'Invoke-Process' $a
    $id = $null; $ix = [array]::IndexOf($ArgumentList, '--id'); if ($ix -ge 0) { $id = $ArgumentList[$ix + 1] }
    switch -Regex ($a) {
        '^--version'      { return [pscustomobject]@{ Code = 0; Output = 'v1.9.25180'; TimedOut = $false } }
        '^source update'  { return [pscustomobject]@{ Code = 0; Output = ''; TimedOut = $false } }
        '^list '          {
            if ($script:Installed.ContainsKey($id)) { return [pscustomobject]@{ Code = 0; Output = "Name  Id  Version`n----`n$id 1.0"; TimedOut = $false } }
            return [pscustomobject]@{ Code = -1978335212; Output = 'No installed package found matching input criteria.'; TimedOut = $false }
        }
        '^(install|upgrade) ' {
            if ($id -eq 'Fail.Pkg') { return [pscustomobject]@{ Code = 1603; Output = 'Installer failed with exit code: 1603'; TimedOut = $false } }
            if ($id -eq 'Reboot.Pkg') { $script:Installed[$id] = $true; return [pscustomobject]@{ Code = 3010; Output = ''; TimedOut = $false } }
            $script:Installed[$id] = $true
            return [pscustomobject]@{ Code = 0; Output = 'Successfully installed'; TimedOut = $false }
        }
    }
    return [pscustomobject]@{ Code = 1; Output = "unexpected args: $a"; TimedOut = $false }
}
function Get-WindowsOptionalFeature { param([switch]$Online, $FeatureName) Record 'Get-WindowsOptionalFeature' $FeatureName; [pscustomobject]@{ State = 'Disabled' } }
function Enable-WindowsOptionalFeature { param([switch]$Online, $FeatureName, [switch]$All, [switch]$NoRestart) Record 'Enable-WindowsOptionalFeature' $FeatureName; [pscustomobject]@{ RestartNeeded = $false } }
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
function Start-Sleep { param($Seconds) }   # no back-off waits in tests

# ---- scenarios --------------------------------------------------------------
Write-Host "`n[1] menu table"
Assert ($MenuItems.Count -eq 11) 'menu has 11 items'
Assert ((@($MenuItems | ForEach-Object Key | Sort-Object -Unique)).Count -eq 11) 'keys are unique'
Assert ((@($MenuItems | ForEach-Object Id | Sort-Object -Unique)).Count -eq 11) 'ids are unique'

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

Write-Host "`n[4] catalog"
Reset-Calls
$cat = Get-SoftwareCatalog
$profiles = Get-SoftwareProfileNames $cat
Assert (@($cat.apps).Count -ge 240) "catalog has $(@($cat.apps).Count) packages"
Assert (($profiles -join ',') -eq 'Runtimes,Standard,Gaming,Technician') 'profiles: Runtimes, Standard, Gaming, Technician'
$keys = @{}; foreach ($a in $cat.apps) { $keys[$a.key] = $a }
$missing = @(); foreach ($p in $profiles) { foreach ($k in $cat.profiles.$p.apps) { if (-not $keys.ContainsKey($k)) { $missing += "$p/$k" } } }
Assert ($missing.Count -eq 0) 'every profile key exists in the catalog'
$badCat = @($cat.apps | Where-Object { $cat.categories -notcontains $_.category })
Assert ($badCat.Count -eq 0) 'every app category is listed in categories'
Assert ((@($cat.apps | Where-Object { $_.type -eq 'winget' -and -not $_.id })).Count -eq 0) 'every winget app has an id'
Assert ((@($cat.apps | Where-Object { $_.category -eq 'Runtimes' })).Count -ge 20) 'Runtimes category present'

Write-Host "`n[5] Software Setup via menu key 4: add Runtimes profile, install, back"
Reset-Calls; $script:KeyQueue = @('4', 'q'); $script:LineQueue = @('1', '', 'q')
Show-Menu 6>$null
$procs = Get-Calls 'Invoke-Process'
$installs = @($procs | Where-Object { $_ -match '^install ' })
$runtimeWinget = @($cat.apps | Where-Object { $cat.profiles.Runtimes.apps -contains $_.key -and $_.type -eq 'winget' })
Assert ($installs.Count -eq $runtimeWinget.Count) "one install per Runtimes winget package ($($installs.Count)/$($runtimeWinget.Count))"
Assert ((@($installs | Where-Object { $_ -notmatch '--scope machine' })).Count -eq 0) 'first variant is machine scope'
Assert ((@($installs | Where-Object { $_ -notmatch '--silent' })).Count -eq 0) 'every install is --silent'
Assert ((@($procs | Where-Object { $_ -match '^source update' })).Count -eq 1) 'winget sources refreshed once'
Assert ((Get-Calls 'Enable-WindowsOptionalFeature') -contains 'NetFx3') 'NetFx3 feature enabled (profile contains netfx35)'
Assert ((Get-Calls 'Wait-AnyKey').Count -eq 2) 'waits after install and after returning to main menu'
$logs = @(Get-ChildItem (Join-Path ([IO.Path]::GetTempPath()) 'win-toolbox') -Filter 'software-setup_*.csv' -ErrorAction SilentlyContinue)
Assert ($logs.Count -ge 1) 'CSV report written to %TEMP%\win-toolbox'

Write-Host "`n[6] dry run + upgrade toggles, category browsing, search, view, clear"
Reset-Calls; $script:LineQueue = @('d', '2', '', 'q')          # dry run on, Standard profile, install (dry), back
Invoke-SoftwareSetup 6>$null
$procs = Get-Calls 'Invoke-Process'
Assert ((@($procs | Where-Object { $_ -match '^(install|upgrade) ' })).Count -eq 0) 'dry run installs nothing'
Assert ((@($procs | Where-Object { $_ -match '^list ' })).Count -gt 0) 'dry run still checks installation state'
Assert ((Get-Calls 'Enable-WindowsOptionalFeature').Count -eq 0) 'dry run does not enable features'
Reset-Calls
$sel = Get-SoftwareSelection
$script:LineQueue = @('1 3', '2-3', '')                          # toggle 1,3 then 2,3 -> 1,2 selected
Show-SoftwareCategory -Catalog $cat -Category 'Browsers' 6>$null
Assert ($sel.Count -eq 2) 'category toggles with ranges (1 3, then 2-3 -> 2 selected)'
$script:LineQueue = @('a', '')
Show-SoftwareCategory -Catalog $cat -Category 'Browsers' 6>$null
Assert ($sel.Count -eq @($cat.apps | Where-Object category -eq 'Browsers').Count) '[a] selects whole category'
$script:LineQueue = @('n', '')
Show-SoftwareCategory -Catalog $cat -Category 'Browsers' 6>$null
Assert ($sel.Count -eq 0) '[n] clears category'
$script:LineQueue = @('i 1', '', '')
Show-SoftwareCategory -Catalog $cat -Category 'Runtimes' 6>$null
Assert ($sel.Count -eq 0) '[i <nr>] shows info without toggling'
$script:LineQueue = @('firefox', '1', '')
Show-SoftwareSearch -Catalog $cat 6>$null
Assert ($sel.Count -eq 1 -and (@($cat.apps | Where-Object { $sel.Contains($_.key) -and $_.name -like '*Firefox*' })).Count -eq 1) 'search + toggle selects Firefox'
$script:LineQueue = @('', 'x', 'q')                              # view selection, clear, back
Show-SoftwareSelection -Catalog $cat 6>$null
$script:LineQueue = @('v', '', 'x', 'q')
$null = Show-SoftwareMenu -Catalog $cat 6>$null
Assert ($sel.Count -eq 0) '[x] clears the selection'
$nums = Expand-NumberList -Text '1 3 5-7 9-8 0 99' -Max 10
Assert (($nums -join ',') -eq '1,3,5,6,7,8,9') 'Expand-NumberList parses ranges, reversed ranges, ignores out-of-range'

Write-Host "`n[7] save / load selection roundtrip"
Reset-Calls
$sel = Get-SoftwareSelection
Add-SoftwareProfile -Catalog $cat -Name 'Technician'
$tmpSel = Join-Path ([IO.Path]::GetTempPath()) 'win-toolbox-smoke-selection.json'
Remove-Item $tmpSel -ErrorAction SilentlyContinue
$script:LineQueue = @($tmpSel, '')
Save-SoftwareSelection 6>$null
Assert (Test-Path $tmpSel) 'selection saved to given path'
$count = $sel.Count
$sel.Clear()
$script:LineQueue = @('')
Import-SoftwareSelection -Catalog $cat -Source $tmpSel 6>$null
Assert ($sel.Count -eq $count -and $count -gt 0) "selection reloaded ($count packages)"
Remove-Item $tmpSel -ErrorAction SilentlyContinue

Write-Host "`n[8] winget engine"
Reset-Calls
$r = Install-WinGetPackage -Id 'Present.Pkg' -Name 'Present' 6>$null
Assert ($r.Status -eq 'Present' -and (@((Get-Calls 'Invoke-Process') | Where-Object { $_ -match '^install' })).Count -eq 0) 'present package is not reinstalled'
$r = Install-WinGetPackage -Id 'Present.Pkg' -Upgrade 6>$null
Assert ($r.Status -eq 'Upgraded' -and (@((Get-Calls 'Invoke-Process') | Where-Object { $_ -match '^upgrade ' })).Count -eq 1) '-Upgrade upgrades present package'
$r = Install-WinGetPackage -Id 'New.Pkg' 6>$null
Assert ($r.Status -eq 'Installed' -and $r.Variant -eq 'machine scope') 'new package installed with machine scope'
$r = Install-WinGetPackage -Id 'Reboot.Pkg' 6>$null
Assert ($r.Status -eq 'Installed' -and $r.Note -eq 'reboot required') '3010 -> installed, reboot required'
Reset-Calls
$r = Install-WinGetPackage -Id 'Fail.Pkg' -Retries 1 6>$null
$attempts = @((Get-Calls 'Invoke-Process') | Where-Object { $_ -match '^install ' })
Assert ($r.Status -eq 'Failed' -and $attempts.Count -eq 6) "failed package tried 3 variants x 2 rounds ($($attempts.Count))"
Assert ($r.Note -match '1603') 'failure note carries winget output'
$r = Install-WinGetPackage -Id 'New.Pkg' -DryRun 6>$null
Assert ($r.Status -eq 'DryRun') 'dry run status'
$r = Install-WinGetPackage -Id '9p7ggfl7dx57' -Name 'Store app' -Source msstore 6>$null
$storeCall = @((Get-Calls 'Invoke-Process') | Where-Object { $_ -match '9p7ggfl7dx57' -and $_ -match '^install' })
Assert ($storeCall.Count -eq 1 -and $storeCall[0] -match '--source msstore' -and $storeCall[0] -notmatch '--scope') '-Source msstore: single variant, no scope'
Assert ((Get-WinGetCodeText 1618) -eq 'another installation is running') 'exit code texts'
Assert ($WinGetState.Flags -contains '--disable-interactivity') 'winget 1.4+ gets --disable-interactivity'

Write-Host "`n[9] winget missing"
Reset-Calls; $script:WingetPath = $null
try { $null = Initialize-WinGet 6>$null; Record 'NoThrow' 1 } catch { Record 'Error' $_.Exception.Message }
Assert ((Get-Calls 'Invoke-RemoteScript') -contains $Urls.WinGetInstall) 'falls back to winget-install script'
Assert ((Get-Calls 'Error').Count -eq 1) 'throws clearly when winget still missing'

Write-Host "`n[10] Windows Update via -Tool update"
Reset-Calls
Show-Menu -Tool update 6>$null
$u = Get-Calls 'Get-WindowsUpdate'
Assert ($u.Count -eq 2) 'search + install'
Assert ($u[1].Install -and $u[1].AcceptAll -and $u[1].AutoReboot) 'installs with -AcceptAll -AutoReboot'
Assert ((Get-Calls 'Install-Module') -contains 'PSWindowsUpdate') 'installs PSWindowsUpdate when missing'
Reset-Calls
Invoke-WindowsUpdate -NoReboot 6>$null
Assert ((Get-Calls 'Get-WindowsUpdate')[1].IgnoreReboot) '-NoReboot -> -IgnoreReboot'

Write-Host "`n[11] Harden System Security"
Reset-Calls; $script:KeyQueue = @('9', 'q')
Show-Menu 6>$null
$w = @((Get-Calls 'Invoke-Process') | Where-Object { $_ -match '^install' })
if ([Environment]::OSVersion.Version.Build -ge 22621) {
    Assert ($w.Count -eq 1 -and $w[0] -match '9p7ggfl7dx57' -and $w[0] -match '--source msstore') 'installs store app via msstore'
} else {
    Assert ($w.Count -eq 0) 'refuses on builds below Win 11 22H2 (this host)'
}

Write-Host "`n[12] menu edge cases"
Reset-Calls; $script:KeyQueue = @('x', 'Q')
Show-Menu 6>$null
Assert ((Get-Calls 'Wait-AnyKey').Count -eq 0) 'unknown key does not run a tool'
Reset-Calls; $script:KeyQueue = @('G', 'q')       # grid -> mocked Out-GridView cancels -> back to text
Show-Menu 6>$null
Assert ((Get-Calls 'Out-GridView').Count -eq 11) 'grid view receives all 11 rows'
Reset-Calls
Show-Menu -Tool nope 6>$null
Assert ((Get-Calls 'Wait-AnyKey').Count -eq 0) '-Tool with unknown id is rejected'
Reset-Calls
Show-Menu -Tool adwcleaner 6>$null
Assert ((Get-Calls 'Start-Process').Count -eq 1) '-Tool adwcleaner runs directly'

Write-Host "`n[13] elevation"
Reset-Calls; $script:Admin = $false
$started = Invoke-Elevated -SelfUrl $SelfUrl -Arguments '-Tool update' 6>$null
$sp = Get-Calls 'Start-Process'
Assert ($started -eq $true) 'reports that an elevated process was started'
Assert ($sp.Count -eq 1 -and $sp[0].Verb -eq 'RunAs') 'uses -Verb RunAs'
Assert (($sp[0].Args -join ' ') -match '-ExecutionPolicy Bypass') 'bypasses execution policy'
Assert (($sp[0].Args -join ' ') -match "irm 'https://example.invalid/win-toolbox.ps1' \| iex|common\.ps1' -Tool update") 're-runs via irm|iex (or the file when run from disk)'
$script:Admin = $true
Assert ((Invoke-Elevated -SelfUrl $SelfUrl 6>$null) -eq $false) 'no-op when already admin'

Write-Host "`n[14] tools refuse without admin (throw, not exit)"
Reset-Calls; $script:Admin = $false
$thrown = 0
try { Invoke-WindowsUpdate 6>$null } catch { $thrown++ }
Add-SoftwareProfile -Catalog $cat -Name 'Runtimes'
try { $null = Invoke-SoftwareInstall -Catalog $cat 6>$null } catch { $thrown++ }
Assert ($thrown -eq 2) 'update + software install refuse without admin'
$script:Admin = $true

Write-Host "`n[15] Inventory: menu options + a full mocked run"
Reset-Calls
# mock CIM/registry/appx so a run works on Linux
$script:InvOut = Join-Path ([IO.Path]::GetTempPath()) ('wt-inv-' + [guid]::NewGuid().ToString('N'))
function Get-CimInstance { param($ClassName, $Namespace, $Filter, [Parameter(Position=0)]$Class)
    $c = if ($ClassName) { $ClassName } else { $Class }
    switch -Wildcard ($c) {
        'Win32_ComputerSystem'  { return [pscustomobject]@{ Manufacturer='ACME'; Model='X1'; Domain='WG'; UserName='u'; SystemType='x64'; TotalPhysicalMemory=17179869184 } }
        'Win32_BIOS'            { return [pscustomobject]@{ SerialNumber='SN123'; Manufacturer='ACME'; SMBIOSBIOSVersion='1.2'; Version='v'; ReleaseDate=$null } }
        'Win32_ComputerSystemProduct' { return [pscustomobject]@{ UUID='uuid-1' } }
        'Win32_SystemEnclosure' { return [pscustomobject]@{ SMBIOSAssetTag='AT1'; ChassisTypes=@(9) } }
        'Win32_BaseBoard'       { return [pscustomobject]@{ Manufacturer='ACME'; Product='MB'; SerialNumber='MB1' } }
        'Win32_OperatingSystem' { return [pscustomobject]@{ Caption='Windows 11 Pro'; Version='10.0.22631'; OSArchitecture='64-bit'; InstallDate=$null; LastBootUpTime=$null } }
        'Win32_Processor'       { return @([pscustomobject]@{ Name='CPU X'; Manufacturer='ACME'; NumberOfCores=8; NumberOfLogicalProcessors=16; MaxClockSpeed=3200; SocketDesignation='S1'; L3CacheSize=16384; VirtualizationFirmwareEnabled=$true }) }
        'Win32_PhysicalMemory'  { return @([pscustomobject]@{ Capacity=8589934592; SMBIOSMemoryType=34; MemoryType=0; DeviceLocator='DIMM0'; ConfiguredClockSpeed=4800; Speed=4800; Manufacturer='ACME'; PartNumber='P1'; SerialNumber='R1' }) }
        'Win32_PhysicalMemoryArray' { return [pscustomobject]@{ MemoryDevices=2 } }
        'Win32_DiskDrive'       { return @([pscustomobject]@{ Index=0; Model='SSD'; SerialNumber='D1'; Size=512110190592; InterfaceType='SCSI'; Partitions=3 }) }
        'Win32_DiskPartition'   { return @() }
        'Win32_LogicalDisk'     { return @([pscustomobject]@{ DeviceID='C:'; VolumeName='OS'; FileSystem='NTFS'; Size=512110190592; FreeSpace=123456789 }) }
        'Win32_VideoController' { return @([pscustomobject]@{ Name='GPU X'; AdapterRAM=4294967296; DriverVersion='30.0'; CurrentHorizontalResolution=1920; CurrentVerticalResolution=1080 }) }
        'Win32_NetworkAdapter'  { return @([pscustomobject]@{ NetConnectionID='Ethernet'; Name='NIC'; MACAddress='00:11:22:33:44:55'; NetEnabled=$true; Index=1; Speed=1000000000 }) }
        'Win32_NetworkAdapterConfiguration' { return [pscustomobject]@{ IPAddress=@('10.0.0.2'); DefaultIPGateway=@('10.0.0.1') } }
        'Win32_Battery'         { return $null }
        'SoftwareLicensingProduct' { return $null }
        default                 { return $null }
    }
}
function Get-PhysicalDisk { @([pscustomobject]@{ DeviceId='0'; MediaType='SSD'; BusType='NVMe'; HealthStatus='Healthy' }) }
function Get-ItemProperty { param($LiteralPath, $Path, $Name)
    $p = if ($LiteralPath) { $LiteralPath } else { $Path }
    if ("$p" -match 'CurrentVersion$') { return [pscustomobject]@{ DisplayVersion='23H2'; CurrentBuild='22631'; UBR='3007' } }
    return $null
}
function Get-Culture { [pscustomobject]@{ Name='de-DE' } }
function Get-AppxPackage { param([switch]$AllUsers, $ErrorAction) @() }
function Get-HotFix { param($ErrorAction) @([pscustomobject]@{ HotFixID='KB5001'; Description='Update'; InstalledOn=(Get-Date '2026-01-01') }) }
function Confirm-SecureBootUEFI { $true }
function Get-ChildItem {
    param([Parameter(ValueFromRemainingArguments)]$args)
    # only the software-registry enumeration matters; return empty so no programs are added
    return @()
}
$InventoryState.OutputMode = 'Custom'; $InventoryState.OutputPath = $script:InvOut; $InventoryState.Software = 'all'
$res = Invoke-InventoryRun 6>$null
Assert ($res.Detail -and (Test-Path $res.Detail)) 'inventory writes detail CSV'
Assert ($res.Overview -and (Test-Path $res.Overview)) 'inventory appends overview CSV'
Assert ($res.WriteErrors -eq 0) 'inventory run without write errors'
$detail = Import-Csv $res.Detail -Delimiter ';'
Assert (($detail | Where-Object { $_.Kategorie -eq 'System' -and $_.Feld -eq 'Seriennummer' }).Wert -eq 'SN123') 'German CSV schema (Kategorie;Feld;Wert) with real data'
Assert (($detail[0].PSObject.Properties.Name -join ';') -eq 'Zeitstempel;Hostname;Kategorie;Feld;Wert') 'detail header stays German'
$ov = Import-Csv $res.Overview -Delimiter ';'
Assert ($ov[0].PSObject.Properties.Name -contains 'Akku_Gesundheit_Prozent') 'overview keeps German column names'
# second run appends (overview grows), header-migration path
$res2 = Invoke-InventoryRun 6>$null
Assert (@(Import-Csv $res2.Overview -Delimiter ';').Count -eq 2) 'overview is appended on second run'
Assert ((Get-InventoryOutputPath) -eq $script:InvOut) 'custom output path is used'
Remove-Item $script:InvOut -Recurse -Force -ErrorAction SilentlyContinue
# output mode toggles via menu
Reset-Calls; $script:LineQueue = @('1', '2', 'q')
$InventoryState.OutputMode = 'Custom'
$null = Show-InventoryMenu 6>$null
Assert ($InventoryState.OutputMode -eq 'CurrentDir') 'menu [1][2] switches output to current directory'

Write-Host "`n[16] Clean Traces: dry run default, execute toggle, categories"
Reset-Calls
Assert ($TraceState.Execute -eq $false) 'dry run is the default'
$script:RunMRUPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU'
$script:RegStore = @{ $script:RunMRUPath = @{ a = '1' } }
function Test-Path { param([Parameter(Position=0)]$Path, $LiteralPath) $p = if ($LiteralPath) { $LiteralPath } else { $Path }; return $script:RegStore.ContainsKey("$p") }
function Get-Item { param($LiteralPath) [pscustomobject]@{ Property = @($script:RegStore["$LiteralPath"].Keys) } }
function Get-ChildItem { param([Parameter(ValueFromRemainingArguments)]$args) @() }
function Remove-ItemProperty { param($LiteralPath, $Name, [switch]$Force, $ErrorAction) $script:RegStore["$LiteralPath"].Remove($Name) }
function Get-PSReadLineOption { [pscustomobject]@{ HistorySavePath = 'C:\nope\history.txt' } }
# dry run: nothing removed
$TraceState.History = $false; $TraceState.Dialogs = $true; $TraceState.Recent = $false; $TraceState.Temp = $false; $TraceState.RecycleBin = $false
$TraceState.Execute = $false
$c = Invoke-TracesRun 6>$null
Assert ($c.Removed -eq 0 -and $c.Skipped -ge 1) 'dry run removes nothing but counts would-be removals'
Assert ($script:RegStore[$script:RunMRUPath].Count -eq 1) 'dry run leaves the registry untouched'
# clear-regkey targets the real path in a real run
$hit = $false
function Clear-RegKey { param($Path, $What) if ($Path -match 'RunMRU') { $script:hitRunMRU = $true } }
$script:hitRunMRU = $false
Clear-Dialogs 6>$null
Assert ($script:hitRunMRU) 'Clean Traces clears the RunMRU key'
# menu: mode toggle guarded by confirmation
Reset-Calls
function Confirm-Action { param($Question) return $true }
$script:LineQueue = @('m', 'q')
$null = Show-TracesMenu 6>$null
Assert ($TraceState.Execute -eq $true) '[m] with confirmation switches to EXECUTE'
$TraceState.Execute = $false

Write-Host "`n[15] dist files"
foreach ($f in Get-ChildItem (Join-Path $root 'dist') -Filter *.ps1) {
    $text = Get-Content $f.FullName -Raw
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
    Assert ($errors.Count -eq 0) "$($f.Name) parses"
    Assert ($text -match "`r`n" -and $text -notmatch "[^`r]`n") "$($f.Name) is CRLF"
    Assert ($text -match '(?m)^& \{\r?$' -and $text.TrimEnd().EndsWith('}')) "$($f.Name) is wrapped in & { }"
    Assert ($text -match '\$SelfUrl = ''https://raw\.githubusercontent\.com/Bladeage/win-toolbox/main/dist/') "$($f.Name) has SelfUrl baked in"
    Assert ($text -notmatch '[^\x00-\x7F]') "$($f.Name) is ASCII-only"
    if ($f.Name -in 'win-toolbox.ps1', 'software-setup.ps1') {
        Assert ($text -match '\$CatalogJson = @''') "$($f.Name) embeds the catalog"
    }
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:Pass, $script:Fail) -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
if ($script:Fail) { exit 1 } else { exit 0 }   # explicit: mocks may leave $LASTEXITCODE non-zero, CI pwsh shell would propagate it
