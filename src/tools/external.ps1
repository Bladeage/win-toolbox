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

function Invoke-WinScript {
    <# flick9000/winscript - debloat, privacy, performance, app installer. #>
    Write-Title 'WinScript (flick9000)'
    Invoke-RemoteScript -Url $Urls.WinScript -Name 'WinScript'
}
