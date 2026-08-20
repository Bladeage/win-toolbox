# ---------------------------------------------------------------------------
# menu.ps1 - the all-in-one text menu (with optional Out-GridView mode).
# ---------------------------------------------------------------------------

$MenuItems = @(
    @{ Key = '1'; Id = 'activate';   Name = 'Activate Windows / Office';  Description = 'Microsoft Activation Scripts (massgrave.dev)'; Action = { Invoke-MAS } },
    @{ Key = '2'; Id = 'update';     Name = 'Windows Update';             Description = 'Install all pending updates (PSWindowsUpdate)';  Action = { Invoke-WindowsUpdate } },
    @{ Key = '3'; Id = 'winget';     Name = 'Install / repair WinGet';    Description = 'winget-install by asheroto';                     Action = { Install-WinGet -Force } },
    @{ Key = '4'; Id = 'software';   Name = 'Software Setup';             Description = 'Profiles (Runtimes / Standard / Gaming / Technician) + 250-app catalog via winget'; Action = { Invoke-SoftwareSetup } },
    @{ Key = '5'; Id = 'office';     Name = 'Office Tool Plus';           Description = 'Download / deploy Microsoft Office';            Action = { Invoke-OfficeToolPlus } },
    @{ Key = '6'; Id = 'winutil';    Name = 'WinUtil';                    Description = "Chris Titus Tech's Windows utility";            Action = { Invoke-WinUtil } },
    @{ Key = '7'; Id = 'winscript';  Name = 'WinScript';                  Description = 'flick9000/winscript - debloat & privacy';        Action = { Invoke-WinScript } },
    @{ Key = '8'; Id = 'adwcleaner'; Name = 'AdwCleaner';                 Description = 'Malwarebytes adware cleaner';                    Action = { Invoke-AdwCleaner } },
    @{ Key = '9'; Id = 'harden';     Name = 'Harden System Security';     Description = 'HotCakeX hardening app (Win 11 22H2+, MS Store)';  Action = { Install-HardenSystemSecurity } }
)

function Show-Banner {
    try { $Host.UI.RawUI.WindowTitle = "win-toolbox v$ToolboxVersion" } catch { Write-Verbose "cannot set window title: $_" }
    Clear-Host
    Write-Host ''
    Write-Host '  win-toolbox' -ForegroundColor Cyan -NoNewline
    Write-Host "  v$ToolboxVersion" -ForegroundColor DarkGray
    Write-Host '  https://github.com/Bladeage/win-toolbox' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-TextMenu {
    Show-Banner
    foreach ($item in $MenuItems) {
        Write-Host ("  [{0}] " -f $item.Key) -ForegroundColor Yellow -NoNewline
        Write-Host ("{0,-28}" -f $item.Name) -NoNewline
        Write-Host $item.Description -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '  [G] Grid view    [Q] Quit' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Select: ' -NoNewline
    return Read-MenuKey
}

function Read-MenuKey {
    # Returns the pressed key as a one-character string ('Q' for Escape). Replaced by tests/smoke.ps1.
    $key = [Console]::ReadKey($true)
    if ($key.Key -eq 'Escape') { return 'Q' }
    return [string]$key.KeyChar
}

function Show-GridMenu {
    # Returns the selected key, or $null when cancelled / unavailable.
    if (-not (Get-Command Out-GridView -ErrorAction SilentlyContinue)) {
        Write-Warn 'Out-GridView is not available in this PowerShell - falling back to the text menu.'
        Start-Sleep -Seconds 2
        return $null
    }
    $rows = $MenuItems | ForEach-Object {
        [pscustomobject]@{ Key = $_.Key; Tool = $_.Name; Description = $_.Description }
    }
    $selection = $rows | Out-GridView -Title "win-toolbox v$ToolboxVersion - pick a tool" -OutputMode Single
    if ($selection) { return $selection.Key }
    return $null
}

function Invoke-MenuItem {
    param([Parameter(Mandatory)][string]$Selector)
    $item = $MenuItems | Where-Object { $_.Key -eq $Selector -or $_.Id -eq $Selector } | Select-Object -First 1
    if (-not $item) {
        Write-Warn "Unknown selection '$Selector'."
        Start-Sleep -Seconds 1
        return
    }
    Clear-Host
    try {
        & $item.Action
    } catch {
        Write-Fail "$($item.Name) failed: $_"
    }
    Wait-AnyKey 'Press any key to return to the menu...'
}

function Show-Menu {
    <#
    .SYNOPSIS
        Runs the interactive menu, or a single tool when -Tool is given (e.g. -Tool update).
    #>
    param([string]$Tool)

    if ($Tool) {
        Invoke-MenuItem -Selector $Tool
        return
    }

    $mode = 'text'
    while ($true) {
        if ($mode -eq 'grid') {
            $key = Show-GridMenu
            if ($null -eq $key) { $mode = 'text'; continue }
        } else {
            $key = Show-TextMenu
        }
        switch -Regex ($key) {
            '^[qQ]$' { Write-Host ''; return }
            '^[gG]$' { $mode = 'grid'; break }
            default  { Invoke-MenuItem -Selector $key }
        }
    }
}
