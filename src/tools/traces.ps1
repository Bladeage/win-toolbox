# ---------------------------------------------------------------------------
# tools/traces.ps1 - remove the technician's working traces in the current user's account.
# English port of Spuren-Entfernen.ps1. Runs in the CONTEXT OF THE LOGGED-IN USER (HKCU +
# profile), not as admin - otherwise it would clean the admin profile. Dry run is the default;
# only "Execute" actually deletes. Deliberately does NOT touch Windows event logs (they belong
# to the device owner) or the USB device history.
# ---------------------------------------------------------------------------

$TraceState = @{
    Execute    = $false
    History    = $true
    Dialogs    = $true
    Recent     = $true
    Temp       = $true
    RecycleBin = $false
}
$TraceCounters = @{ Removed = 0; Skipped = 0; Errors = 0 }

function Remove-Trace {
    <# Removes one target if present, honouring dry-run and counting. #>
    param([Parameter(Mandatory)][string]$What, [scriptblock]$Action, [scriptblock]$Present = { $true })
    $there = $false
    try { $there = [bool](& $Present) } catch { $there = $false }
    if (-not $there) { return }
    if (-not $TraceState.Execute) {
        Write-Host ("   [would] {0}" -f $What) -ForegroundColor Yellow
        $TraceCounters.Skipped++
        return
    }
    try { & $Action; Write-Host ("   [gone] {0}" -f $What) -ForegroundColor Green; $TraceCounters.Removed++ }
    catch { Write-Host ("   [X]    {0} - {1}" -f $What, $_.Exception.Message) -ForegroundColor Red; $TraceCounters.Errors++ }
}

function Remove-RegValue {
    param([string]$Path, [string]$Name, [string]$What)
    Remove-Trace -What $What `
        -Present { (Test-Path -LiteralPath $Path) -and ($null -ne (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue)) } `
        -Action  { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop }
}

function Clear-RegKey {
    param([string]$Path, [string]$What)
    Remove-Trace -What $What `
        -Present { (Test-Path -LiteralPath $Path) -and ((@(Get-ChildItem -LiteralPath $Path -ErrorAction SilentlyContinue).Count -gt 0) -or (@((Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue).Property).Count -gt 0)) } `
        -Action  {
            Get-ChildItem -LiteralPath $Path -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            foreach ($n in (Get-Item -LiteralPath $Path).Property) { if ($n -ne '(Default)') { Remove-ItemProperty -LiteralPath $Path -Name $n -Force -ErrorAction SilentlyContinue } }
        }
}

function Clear-ShellHistory {
    Write-Host ''; Write-Host '== Shell history' -ForegroundColor Cyan
    $psr = $null
    try { $psr = (Get-PSReadLineOption -ErrorAction SilentlyContinue).HistorySavePath } catch { $null = $_ }
    if (-not $psr) { $psr = Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt' }
    Remove-Trace -What ("PowerShell history file: {0}" -f $psr) -Present { Test-Path -LiteralPath $psr } -Action { Remove-Item -LiteralPath $psr -Force -ErrorAction Stop }
    if ($TraceState.Execute) {
        try { Clear-History -ErrorAction SilentlyContinue } catch { $null = $_ }
        try { [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory() } catch { $null = $_ }
    }
    Write-Host '   CMD keeps no on-disk history - nothing to remove.' -ForegroundColor DarkGray
}

function Clear-Dialogs {
    Write-Host ''; Write-Host '== Run dialog and address bars' -ForegroundColor Cyan
    $hk = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
    Clear-RegKey "$hk\RunMRU"                      'Run dialog (Win+R)'
    Clear-RegKey "$hk\TypedPaths"                  'Explorer address bar (typed paths)'
    Clear-RegKey "$hk\RecentDocs"                  'Recently opened documents (RecentDocs)'
    Clear-RegKey "$hk\ComDlg32\LastVisitedPidlMRU" 'Open/Save - last visited folders'
    Clear-RegKey "$hk\ComDlg32\OpenSavePidlMRU"    'Open/Save - last used files'
    Clear-RegKey "$hk\WordWheelQuery"              'Explorer search box history'
}

function Clear-RecentItems {
    Write-Host ''; Write-Host '== Recent items and jump lists' -ForegroundColor Cyan
    $recent = Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
    foreach ($u in @($recent, (Join-Path $recent 'AutomaticDestinations'), (Join-Path $recent 'CustomDestinations'))) {
        Remove-Trace -What ("Contents of {0}" -f $u) `
            -Present { (Test-Path -LiteralPath $u) -and (@(Get-ChildItem -LiteralPath $u -Force -ErrorAction SilentlyContinue).Count -gt 0) } `
            -Action  { Get-ChildItem -LiteralPath $u -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue }
    }
}

function Clear-TempFiles {
    Write-Host ''; Write-Host '== Temporary files' -ForegroundColor Cyan
    $targets = @($env:TEMP)
    if (Test-IsAdmin) { $targets += (Join-Path $env:SystemRoot 'Temp') }
    foreach ($t in ($targets | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $t)) { continue }
        $count = 0
        try { $count = @(Get-ChildItem -LiteralPath $t -Force -ErrorAction SilentlyContinue).Count } catch { $null = $_ }
        if ($count -eq 0) { continue }
        Remove-Trace -What ("{0} entries in {1}" -f $count, $t) -Present { $true } `
            -Action { Get-ChildItem -LiteralPath $t -Force -ErrorAction SilentlyContinue | ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction Stop } catch { $null = $_ } } }
    }
}

function Clear-RecycleBinTrace {
    Write-Host ''; Write-Host '== Recycle bin' -ForegroundColor Cyan
    if (-not $TraceState.Execute) { Write-Host '   [would] empty the recycle bin' -ForegroundColor Yellow; $TraceCounters.Skipped++; return }
    try { Clear-RecycleBin -Force -ErrorAction Stop; Write-Host '   [gone] recycle bin emptied' -ForegroundColor Green; $TraceCounters.Removed++ }
    catch {
        $hr = 0; try { $hr = $_.Exception.HResult } catch { $null = $_ }
        if ($hr -eq -2147418113 -or $hr -eq -2147024751 -or "$($_.Exception.Message)" -match 'empty') { Write-Host '   recycle bin was already empty.' -ForegroundColor DarkGray }
        else { Write-Host ("   [X]    recycle bin: {0}" -f $_.Exception.Message) -ForegroundColor Red; $TraceCounters.Errors++ }
    }
}

function Show-TracesMenu {
    <# Returns $true to run, $false to go back. #>
    while ($true) {
        Clear-Host
        Write-Title 'Clean Traces'
        Write-Host '   Removes the technician''s working traces in the CURRENT user account (HKCU + profile).' -ForegroundColor DarkGray
        Write-Host '   Event logs and USB device history are deliberately left alone.' -ForegroundColor DarkGray
        Write-Host ''
        $on = { param($b) if ($b) { 'on ' } else { 'off' } }
        Write-Host ("   [1] Shell history   : {0}  PSReadLine file + current session" -f (& $on $TraceState.History))
        Write-Host ("   [2] Dialogs         : {0}  Run (Win+R), address bar, open/save, RecentDocs" -f (& $on $TraceState.Dialogs))
        Write-Host ("   [3] Recent items    : {0}  Recent folder and jump lists" -f (& $on $TraceState.Recent))
        Write-Host ("   [4] Temp files      : {0}  %TEMP% (+ C:\Windows\Temp when admin)" -f (& $on $TraceState.Temp))
        Write-Host ("   [5] Recycle bin     : {0}  empty the recycle bin (off by default)" -f (& $on $TraceState.RecycleBin))
        Write-Host ''
        $modeText = if ($TraceState.Execute) { 'EXECUTE - will delete' } else { 'dry run - shows only what would be removed' }
        $modeColor = if ($TraceState.Execute) { 'Red' } else { 'Yellow' }
        Write-Host ("   [m] Mode            : {0}" -f $modeText) -ForegroundColor $modeColor
        Write-Host ''
        Write-Host '   [Enter] run          [q] back' -ForegroundColor Green
        Write-Host ''
        $e = (Read-MenuLine '  Choice').ToLower()
        switch ($e) {
            ''  { return $true }
            'q' { return $false }
            '1' { $TraceState.History = -not $TraceState.History }
            '2' { $TraceState.Dialogs = -not $TraceState.Dialogs }
            '3' { $TraceState.Recent = -not $TraceState.Recent }
            '4' { $TraceState.Temp = -not $TraceState.Temp }
            '5' { $TraceState.RecycleBin = -not $TraceState.RecycleBin }
            'm' {
                if (-not $TraceState.Execute) {
                    if (Confirm-Action '  Switch to EXECUTE (this will delete)?') { $TraceState.Execute = $true }
                } else { $TraceState.Execute = $false }
            }
        }
    }
}

function Invoke-TracesRun {
    <# Runs the selected categories. Returns the counters hashtable. #>
    $TraceCounters.Removed = 0; $TraceCounters.Skipped = 0; $TraceCounters.Errors = 0
    $log = Start-Log -Name 'clean-traces'
    Write-Title 'Clean Traces'
    Write-Host ("   Host: {0}   User: {1}" -f $env:COMPUTERNAME, $env:USERNAME) -ForegroundColor DarkGray
    if ($TraceState.Execute) { Write-Host '   Mode: DELETING' -ForegroundColor Red } else { Write-Host '   Mode: dry run - nothing is deleted' -ForegroundColor Yellow }
    Write-LogLine ("mode: {0}" -f $(if ($TraceState.Execute) { 'execute' } else { 'dry run' }))

    if ($TraceState.History) { Clear-ShellHistory }
    if ($TraceState.Dialogs) { Clear-Dialogs }
    if ($TraceState.Recent) { Clear-RecentItems }
    if ($TraceState.Temp) { Clear-TempFiles }
    if ($TraceState.RecycleBin) { Clear-RecycleBinTrace }

    Write-Host ''
    if ($TraceState.Execute) {
        Write-Host ("   Removed: {0}   Errors: {1}" -f $TraceCounters.Removed, $TraceCounters.Errors) -ForegroundColor $(if ($TraceCounters.Errors) { 'Yellow' } else { 'Green' })
    } else {
        Write-Host ("   Dry run: {0} items would be removed. Switch mode to [m] EXECUTE to delete." -f $TraceCounters.Skipped) -ForegroundColor Yellow
    }
    if ($TraceState.Execute -and ($TraceState.Dialogs -or $TraceState.Recent)) {
        Write-Host '   Note: jump lists and history disappear from the UI only after restarting Explorer or signing in again.' -ForegroundColor DarkGray
    }
    if ($log) { Write-Host ("   Log: {0}" -f $log) -ForegroundColor DarkGray }
    return $TraceCounters
}

function Invoke-CleanTraces {
    <# Menu entry: options menu (dry-run default), then the run. #>
    while (Show-TracesMenu) {
        $null = Invoke-TracesRun
        Wait-AnyKey 'Press any key to return to the Clean Traces menu...'
    }
}
