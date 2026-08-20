# ---------------------------------------------------------------------------
# tools/redists.ps1 - PC gaming redistributables + common tools via winget.
# Successor of the PC-Gaming-Redists AIOInstaller.bat (harryeffinpotter/skrimix),
# rewritten in PowerShell with an explicit package list instead of `winget search` scraping.
# ---------------------------------------------------------------------------

$RedistPackages = @(
    # --- Visual C++ runtimes (x86 + x64, every generation still used by games) ---
    @{ Group = 'Visual C++'; Id = 'Microsoft.VCRedist.2005.x86' },
    @{ Group = 'Visual C++'; Id = 'Microsoft.VCRedist.2005.x64' },
    @{ Group = 'Visual C++'; Id = 'Microsoft.VCRedist.2008.x86' },
    @{ Group = 'Visual C++'; Id = 'Microsoft.VCRedist.2008.x64' },
    @{ Group = 'Visual C++'; Id = 'Microsoft.VCRedist.2010.x86' },
    @{ Group = 'Visual C++'; Id = 'Microsoft.VCRedist.2010.x64' },
    @{ Group = 'Visual C++'; Id = 'Microsoft.VCRedist.2012.x86' },
    @{ Group = 'Visual C++'; Id = 'Microsoft.VCRedist.2012.x64' },
    @{ Group = 'Visual C++'; Id = 'Microsoft.VCRedist.2013.x86' },
    @{ Group = 'Visual C++'; Id = 'Microsoft.VCRedist.2013.x64' },
    @{ Group = 'Visual C++'; Id = 'Microsoft.VCRedist.2015+.x86' },
    @{ Group = 'Visual C++'; Id = 'Microsoft.VCRedist.2015+.x64' },
    @{ Group = 'Visual C++'; Id = 'Microsoft.VCLibs.Desktop.14' },        # VCLibs for Store / Game Pass apps
    # --- .NET desktop runtimes ---
    @{ Group = '.NET'; Id = 'Microsoft.DotNet.DesktopRuntime.3_1' },
    @{ Group = '.NET'; Id = 'Microsoft.DotNet.DesktopRuntime.5' },
    @{ Group = '.NET'; Id = 'Microsoft.DotNet.DesktopRuntime.6' },
    @{ Group = '.NET'; Id = 'Microsoft.DotNet.DesktopRuntime.7' },
    @{ Group = '.NET'; Id = 'Microsoft.DotNet.DesktopRuntime.8' },
    @{ Group = '.NET'; Id = 'Microsoft.DotNet.DesktopRuntime.9' },
    @{ Group = '.NET'; Id = 'Microsoft.DotNet.DesktopRuntime.10' },
    # --- DirectX / XNA ---
    @{ Group = 'DirectX & XNA'; Id = 'Microsoft.DirectX' },
    @{ Group = 'DirectX & XNA'; Id = 'Microsoft.XNARedist' },
    # --- common tools ---
    @{ Group = 'Tools'; Id = '7zip.7zip' },
    @{ Group = 'Tools'; Id = 'Microsoft.PowerShell' },
    @{ Group = 'Tools'; Id = 'Microsoft.WindowsTerminal' },
    @{ Group = 'Java'; Id = 'Oracle.JavaRuntimeEnvironment' },
    @{ Group = 'Java'; Id = 'Oracle.JDK.22' }
)

function Install-GamingRedists {
    <#
    .SYNOPSIS
        Installs all Visual C++ / .NET runtimes, DirectX, XNA and a few common tools via winget.
    .PARAMETER Group
        Only install packages of the given group(s), e.g. -Group 'Visual C++','.NET'.
    .PARAMETER Force
        Reinstall packages that are already present (winget --force) - the old
        "scorched earth" behaviour of the batch installer.
    .NOTES
        Requires an elevated shell. Installs WinGet first if it is missing.
    #>
    param(
        [string[]]$Group,
        [switch]$Force
    )

    Write-Title 'PC Gaming Redistributables'
    if (-not (Test-IsAdmin)) { throw 'Administrator rights are required to install redistributables.' }

    Install-WinGet

    $packages = $RedistPackages
    if ($Group) { $packages = $packages | Where-Object { $Group -contains $_.Group } }

    $failed = @()
    foreach ($grp in ($packages | ForEach-Object { $_.Group } | Select-Object -Unique)) {
        Write-Step "$grp"
        foreach ($pkg in ($packages | Where-Object { $_.Group -eq $grp })) {
            if (-not (Install-WinGetPackage -Id $pkg.Id -Force:$Force)) { $failed += $pkg.Id }
        }
    }

    if (-not $Group -or $Group -contains '.NET') {
        Write-Step '.NET Framework 3.5 (Windows feature, needed by older games)'
        try {
            $feature = Get-WindowsOptionalFeature -Online -FeatureName NetFx3
            if ($feature.State -eq 'Enabled') {
                Write-Ok 'already enabled'
            } else {
                $null = Enable-WindowsOptionalFeature -Online -FeatureName NetFx3 -All -NoRestart
                Write-Ok 'enabled'
            }
        } catch {
            Write-Warn "could not enable NetFx3: $_"
            $failed += 'NetFx3'
        }
    }

    Write-Host ''
    if ($failed.Count -eq 0) {
        Write-Ok 'All packages installed.'
    } else {
        Write-Warn "$($failed.Count) package(s) failed: $($failed -join ', ')"
    }
}
