# ---------------------------------------------------------------------------
# tools/windows-update.ps1 - install all pending Windows updates via PSWindowsUpdate.
# ---------------------------------------------------------------------------

function Invoke-WindowsUpdate {
    <#
    .SYNOPSIS
        Installs the PSWindowsUpdate module if needed, then installs every available update.
    .PARAMETER NoReboot
        Do not reboot automatically when an update requires it.
    .NOTES
        Requires an elevated shell.
    #>
    param([switch]$NoReboot)

    Write-Title 'Windows Update (PSWindowsUpdate)'
    if (-not (Test-IsAdmin)) { throw 'Administrator rights are required for Windows Update.' }

    Write-Step 'Checking NuGet package provider...'
    if (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue) {
        Write-Ok 'NuGet provider present.'
    } else {
        Write-Step 'Installing NuGet package provider...'
        $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    }

    Write-Step 'Checking PSWindowsUpdate module...'
    if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
        Write-Ok 'PSWindowsUpdate present.'
    } else {
        Write-Step 'Installing PSWindowsUpdate from the PowerShell Gallery...'
        Install-Module -Name PSWindowsUpdate -Force
    }
    Import-Module PSWindowsUpdate

    Write-Step 'Searching for updates...'
    $updates = @(Get-WindowsUpdate)
    if ($updates.Count -eq 0) {
        Write-Ok 'No updates available - system is up to date.'
        return
    }
    $updates | Format-Table -AutoSize KB, Size, Title | Out-String | Write-Host

    Write-Step "Installing $($updates.Count) update(s)..."
    if ($NoReboot) {
        Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot
    } else {
        Write-Warn 'The system will reboot automatically if an update requires it.'
        Get-WindowsUpdate -Install -AcceptAll -AutoReboot
    }
    Write-Ok 'Windows Update finished.'
}
