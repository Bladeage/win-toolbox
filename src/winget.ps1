# ---------------------------------------------------------------------------
# winget.ps1 - robust winget engine (needs common.ps1).
# ---------------------------------------------------------------------------

# ---- winget ---------------------------------------------------------------
# Robust winget handling, ported from Install-Software.ps1 (the PC-Gaming-Redists successor):
# find winget.exe even when PATH lacks it, run it with a timeout, verify success by the
# real installation state instead of trusting exit codes.

$WinGetState = @{ Path = $null; Version = ''; Flags = @('--accept-source-agreements', '--disable-interactivity'); Ready = $false }

function Invoke-Process {
    <#
    .SYNOPSIS
        Runs an executable with a timeout and captures stdout + stderr.
        Returns @{ Code; Output; TimedOut }. On timeout the whole process tree is killed
        (winget spawns the real installer as a child - .Kill() alone would leave it running).
    #>
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutSeconds = 1200
    )
    $tmp = [IO.Path]::GetTempPath()
    $out = Join-Path $tmp ('win-toolbox-out-{0}.txt' -f [guid]::NewGuid().ToString('N'))
    $err = Join-Path $tmp ('win-toolbox-err-{0}.txt' -f [guid]::NewGuid().ToString('N'))
    try {
        $startArgs = @{ FilePath = $FilePath; PassThru = $true; NoNewWindow = $true; RedirectStandardOutput = $out; RedirectStandardError = $err }
        if ($ArgumentList.Count -gt 0) { $startArgs.ArgumentList = $ArgumentList }
        $p = Start-Process @startArgs
        if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
            try { & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null } catch { $null = $_ }
            try { if (-not $p.HasExited) { $p.Kill() } } catch { $null = $_ }
            return [pscustomobject]@{ Code = -999; Output = 'timeout - process tree terminated'; TimedOut = $true }
        }
        $p.WaitForExit()
        $text = @()
        foreach ($f in @($out, $err)) {
            if (Test-Path -LiteralPath $f) {
                $content = Get-Content -LiteralPath $f -Raw -ErrorAction SilentlyContinue
                if ($content) { $text += $content.Trim() }
            }
        }
        return [pscustomobject]@{ Code = $p.ExitCode; Output = ($text -join "`n").Trim(); TimedOut = $false }
    } catch {
        return [pscustomobject]@{ Code = -998; Output = $_.Exception.Message; TimedOut = $false }
    } finally {
        Remove-Item -LiteralPath $out, $err -ErrorAction SilentlyContinue
    }
}

function Get-WinGetPath {
    <# Finds winget.exe - in elevated shells the PATH alias is often missing. Cached in $WinGetState.Path. #>
    if ($WinGetState.Path -and (Test-Path -LiteralPath $WinGetState.Path)) { return $WinGetState.Path }

    # 1. real package folder under Program Files\WindowsApps (works across accounts)
    $windowsApps = Join-Path $env:ProgramFiles 'WindowsApps'
    if ($windowsApps -and (Test-Path -LiteralPath $windowsApps)) {
        $dirs = Get-ChildItem -LiteralPath $windowsApps -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like 'Microsoft.DesktopAppInstaller_*_x64__*' -or $_.Name -like 'Microsoft.DesktopAppInstaller_*_arm64__*' } |
                Sort-Object Name -Descending
        foreach ($d in $dirs) {
            $p = Join-Path $d.FullName 'winget.exe'
            if (Test-Path -LiteralPath $p) { $WinGetState.Path = $p; return $p }
        }
    }
    # 2. registered Appx package of the current user
    try {
        $pkg = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
        if ($pkg -and $pkg.InstallLocation) {
            $p = Join-Path $pkg.InstallLocation 'winget.exe'
            if (Test-Path -LiteralPath $p) { $WinGetState.Path = $p; return $p }
        }
    } catch { $null = $_ }
    # 3. PATH / execution alias
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { $WinGetState.Path = $cmd.Source; return $cmd.Source }
    if ($env:LOCALAPPDATA) {
        $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
        if (Test-Path -LiteralPath $alias) { $WinGetState.Path = $alias; return $alias }
    }
    return $null
}

function Initialize-WinGet {
    <#
    .SYNOPSIS
        Makes sure winget is usable and returns its path: locates winget.exe, installs it via
        winget-install (asheroto) when missing, detects the version (--disable-interactivity needs 1.4+).
    #>
    if ($WinGetState.Ready) { return $WinGetState.Path }
    $path = Get-WinGetPath
    if (-not $path) {
        Write-Step 'WinGet not found - installing via winget-install (asheroto)...'
        Invoke-RemoteScript -Url $Urls.WinGetInstall -Name 'winget-install'
        Update-SessionPath
        $WinGetState.Path = $null
        $path = Get-WinGetPath
    }
    if (-not $path) { throw 'WinGet is not available. Install "App Installer" from the Microsoft Store, open a new terminal and try again.' }

    $v = Invoke-Process -FilePath $path -ArgumentList @('--version') -TimeoutSeconds 60
    $WinGetState.Version = ($v.Output -replace '[^\d\.]', '').Trim('.')
    $flags = @('--accept-source-agreements')
    $modern = $true
    if ($WinGetState.Version -match '^(\d+)\.(\d+)') {
        if ([int]$Matches[1] -lt 1 -or ([int]$Matches[1] -eq 1 -and [int]$Matches[2] -lt 4)) { $modern = $false }
    }
    if ($modern) { $flags += '--disable-interactivity' } else { Write-Warn 'Old winget version - running without --disable-interactivity.' }
    $WinGetState.Flags = $flags
    $WinGetState.Ready = $true
    Write-Ok ("WinGet {0} ({1})" -f $WinGetState.Version, $path)
    return $path
}

function Install-WinGet {
    <# Menu item: install or repair WinGet via asheroto's winget-install script. #>
    param([switch]$Force)
    Write-Title 'WinGet'
    if ((Get-WinGetPath) -and -not $Force) {
        $null = Initialize-WinGet
        Write-Ok 'WinGet is already installed.'
        return
    }
    Invoke-RemoteScript -Url $Urls.WinGetInstall -Name 'winget-install (asheroto)'
    Update-SessionPath
    $WinGetState.Path = $null; $WinGetState.Ready = $false
    if (-not (Get-WinGetPath)) { throw 'WinGet is still not available in this session. Open a new terminal and try again.' }
    $null = Initialize-WinGet
    Write-Ok 'WinGet ready.'
}

function Update-WinGetSources {
    $r = Invoke-Process -FilePath (Initialize-WinGet) -ArgumentList (@('source', 'update') + $WinGetState.Flags) -TimeoutSeconds 300
    if ($r.Code -ne 0) { Write-Warn 'Could not refresh winget sources - continuing with the cached state.' }
}

function Test-WinGetInstalled {
    <# $true when the package is installed. In doubt returns $false - installing once too often beats silently skipping. #>
    param([Parameter(Mandatory)][string]$Id)
    $r = Invoke-Process -FilePath (Initialize-WinGet) -ArgumentList (@('list', '--exact', '--id', $Id) + $WinGetState.Flags) -TimeoutSeconds 120
    if ($r.Code -ne 0) { return $false }
    if ([string]::IsNullOrWhiteSpace($r.Output)) { return $false }
    if ($r.Output -match 'No installed package') { return $false }
    return $true
}

function Get-WinGetCodeText {
    param([int]$Code)
    switch ($Code) {
        0           { 'success' }
        3010        { 'success, reboot required' }
        1602        { 'cancelled by user' }
        1603        { 'fatal installer error' }
        1618        { 'another installation is running' }
        1641        { 'success, reboot initiated' }
        -999        { 'timeout' }
        -998        { 'process could not be started' }
        -1978335189 { 'no applicable update found' }
        -1978335212 { 'package not found' }
        default     { '0x{0:X8}' -f $Code }
    }
}

function Install-WinGetPackage {
    <#
    .SYNOPSIS
        Installs (or upgrades) one package robustly and prints a one-line result.
    .DESCRIPTION
        Checks the real installation state first, then tries winget with several call variants
        (machine scope -> user scope -> no source pinning), retries with back-off, and finally
        verifies by winget list - exit codes differ between winget versions and are not trusted.
        Returns [pscustomobject]@{ Status = Installed|Upgraded|Present|Failed|DryRun; Code; Note; Variant }.
    .PARAMETER Upgrade
        Also upgrade when already installed (default: leave installed packages alone).
    .PARAMETER DryRun
        Only report what would happen.
    .PARAMETER Source
        Restrict to one winget source (e.g. msstore). Default: winget source with fallbacks.
    #>
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$Name = $Id,
        [string]$Source,
        [switch]$Upgrade,
        [switch]$DryRun,
        [int]$Retries = 2,
        [int]$TimeoutMinutes = 20
    )
    $winget = Initialize-WinGet
    $label = "   {0,-42} " -f $Name
    $present = Test-WinGetInstalled -Id $Id

    if ($present -and -not $Upgrade) {
        Write-Host $label -NoNewline; Write-Host 'present' -ForegroundColor DarkGreen
        Write-LogLine "$Name ($Id): present"
        return [pscustomobject]@{ Status = 'Present'; Code = 0; Note = ''; Variant = '' }
    }
    if ($DryRun) {
        $what = if ($present) { 'would upgrade' } else { 'would install' }
        Write-Host $label -NoNewline; Write-Host $what -ForegroundColor Cyan
        return [pscustomobject]@{ Status = 'DryRun'; Code = 0; Note = $what; Variant = '' }
    }

    $verb = if ($present) { 'upgrade' } else { 'install' }
    $base = @($verb, '--exact', '--id', $Id, '--silent', '--accept-package-agreements') + $WinGetState.Flags
    if ($Source) {
        $variants = @(@{ Text = $Source; Args = $base + @('--source', $Source) })
    } else {
        $variants = @(
            @{ Text = 'machine scope'; Args = $base + @('--source', 'winget', '--scope', 'machine') },
            @{ Text = 'user scope';    Args = $base + @('--source', 'winget') },
            @{ Text = 'any source';    Args = $base }
        )
    }
    Write-Host $label -NoNewline
    Write-Host ("{0}..." -f $verb) -ForegroundColor DarkGray -NoNewline

    $last = $null
    $stop = $false
    for ($round = 0; $round -le $Retries -and -not $stop; $round++) {
        if ($round -gt 0) { Start-Sleep -Seconds (5 * $round) }
        foreach ($v in $variants) {
            $r = Invoke-Process -FilePath $winget -ArgumentList $v.Args -TimeoutSeconds ($TimeoutMinutes * 60)
            $last = $r
            Write-LogLine ("{0} ({1}): winget {2} [{3}] -> {4} ({5})" -f $Name, $Id, $verb, $v.Text, $r.Code, (Get-WinGetCodeText $r.Code))
            if ($r.Code -eq 0) {
                $status = if ($present) { 'Upgraded' } else { 'Installed' }
                Write-Host ("`r" + $label) -NoNewline; Write-Host $status.ToLower() -ForegroundColor Green
                return [pscustomobject]@{ Status = $status; Code = 0; Note = ''; Variant = $v.Text }
            }
            if ($r.Code -eq 3010 -or $r.Code -eq 1641) {
                Write-Host ("`r" + $label) -NoNewline; Write-Host 'installed, reboot required' -ForegroundColor Green
                return [pscustomobject]@{ Status = 'Installed'; Code = $r.Code; Note = 'reboot required'; Variant = $v.Text }
            }
            if ($r.Code -eq -1978335189 -and $present) {
                Write-Host ("`r" + $label) -NoNewline; Write-Host 'up to date' -ForegroundColor DarkGreen
                return [pscustomobject]@{ Status = 'Present'; Code = $r.Code; Note = 'no update available'; Variant = '' }
            }
            if ($r.Code -eq 1618) { break }          # another installer is running - wait, do not switch variants
            if ($r.TimedOut) { $stop = $true; break } # a hanging installer hangs again - do not burn more timeouts
        }
    }

    # last resort: did it work despite the error code?
    if (Test-WinGetInstalled -Id $Id) {
        if ($present) {
            Write-Host ("`r" + $label) -NoNewline; Write-Host ("present (upgrade failed: {0})" -f (Get-WinGetCodeText $last.Code)) -ForegroundColor Yellow
            return [pscustomobject]@{ Status = 'Present'; Code = $last.Code; Note = 'upgrade failed'; Variant = '' }
        }
        Write-Host ("`r" + $label) -NoNewline; Write-Host ("installed (winget reported {0})" -f (Get-WinGetCodeText $last.Code)) -ForegroundColor Green
        return [pscustomobject]@{ Status = 'Installed'; Code = $last.Code; Note = 'present despite error code'; Variant = '' }
    }
    $short = ''
    if ($last -and $last.Output) { $short = (($last.Output -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 2) -join ' / ') }
    Write-Host ("`r" + $label) -NoNewline; Write-Host ("FAILED ({0})" -f (Get-WinGetCodeText $last.Code)) -ForegroundColor Red
    if ($short) { Write-Host ("      {0}" -f $short) -ForegroundColor DarkGray }
    return [pscustomobject]@{ Status = 'Failed'; Code = $last.Code; Note = $short; Variant = '' }
}

function Install-WindowsFeatureItem {
    <# Enables a Windows optional feature (e.g. NetFx3). Same result object as Install-WinGetPackage. #>
    param([Parameter(Mandatory)][string]$FeatureName, [string]$Name = $FeatureName, [switch]$DryRun)
    $label = "   {0,-42} " -f $Name
    try { $f = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction Stop }
    catch {
        Write-Host $label -NoNewline; Write-Host "FAILED (cannot query: $($_.Exception.Message))" -ForegroundColor Red
        return [pscustomobject]@{ Status = 'Failed'; Code = -1; Note = $_.Exception.Message; Variant = '' }
    }
    if ($f.State -eq 'Enabled') {
        Write-Host $label -NoNewline; Write-Host 'present' -ForegroundColor DarkGreen
        return [pscustomobject]@{ Status = 'Present'; Code = 0; Note = ''; Variant = '' }
    }
    if ($DryRun) {
        Write-Host $label -NoNewline; Write-Host 'would enable' -ForegroundColor Cyan
        return [pscustomobject]@{ Status = 'DryRun'; Code = 0; Note = 'would enable'; Variant = '' }
    }
    try {
        $r = Enable-WindowsOptionalFeature -Online -FeatureName $FeatureName -All -NoRestart -ErrorAction Stop
        $note = if ($r.RestartNeeded) { 'reboot required' } else { '' }
        Write-Host $label -NoNewline; Write-Host 'enabled' -ForegroundColor Green
        return [pscustomobject]@{ Status = 'Installed'; Code = 0; Note = $note; Variant = '' }
    } catch {
        Write-Host $label -NoNewline; Write-Host "FAILED ($($_.Exception.Message))" -ForegroundColor Red
        Write-Host '      Common cause: Windows Update blocked by policy (WSUS) - needs install media as source.' -ForegroundColor DarkGray
        return [pscustomobject]@{ Status = 'Failed'; Code = -1; Note = $_.Exception.Message; Variant = '' }
    }
}
