# ---------------------------------------------------------------------------
# tools/external.ps1 - thin wrappers around well-known third-party irm|iex scripts.
# Each one runs code from the internet - the URL is shown before it runs.
# ---------------------------------------------------------------------------

function Invoke-MAS {
    <# Microsoft Activation Scripts (massgrave.dev) - Windows / Office activation. #>
    Write-Title 'Microsoft Activation Scripts (MAS)'
    Invoke-RemoteScript -Url $Urls.MAS -Name 'MAS'
}

function Invoke-OfficeToolPlus {
    <# Office Tool Plus - download/deploy/manage Microsoft Office. #>
    Write-Title 'Office Tool Plus'
    Invoke-RemoteScript -Url $Urls.OfficeToolPlus -Name 'Office Tool Plus'
}

function Invoke-WinUtil {
    <# Chris Titus Tech's Windows Utility - tweaks, debloat, installs. #>
    Write-Title 'WinUtil (Chris Titus Tech)'
    Invoke-RemoteScript -Url $Urls.WinUtil -Name 'WinUtil'
}

function Install-HardenSystemSecurity {
    <#
    .SYNOPSIS
        Installs HotCakeX's "Harden System Security" app (Microsoft Store) and starts it.
    .NOTES
        Successor of the deprecated Harden-Windows-Security-Module. Needs Windows 11 22H2+
        and an elevated shell.
    #>
    Write-Title 'Harden System Security (HotCakeX)'
    $build = [Environment]::OSVersion.Version.Build
    if ($build -lt 22621) {
        throw "Harden System Security needs Windows 11 22H2 or newer (this is build $build)."
    }
    if (-not (Test-IsAdmin)) { throw 'Administrator rights are required.' }
    Install-WinGet
    Write-Step 'Installing from the Microsoft Store via winget...'
    if (Install-WinGetPackage -Id '9p7ggfl7dx57' -Label 'Harden System Security' -Source msstore) {
        Write-Step 'Starting Harden System Security...'
        Start-Process 'shell:AppsFolder\$((Get-StartApps | Where-Object Name -eq "Harden System Security" | Select-Object -First 1).AppID)' -ErrorAction SilentlyContinue
        Write-Ok 'Done. If the app did not open, find "Harden System Security" in the Start menu.'
    }
}

function Invoke-WinScript {
    <# flick9000/winscript - debloat, privacy, performance, app installer. #>
    Write-Title 'WinScript (flick9000)'
    Invoke-RemoteScript -Url $Urls.WinScript -Name 'WinScript'
}
