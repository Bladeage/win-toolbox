# ---------------------------------------------------------------------------
# tools/software.ps1 - Software Setup: profiles + catalog of winget packages.
# English port of Install-Software.ps1 (the PC-Gaming-Redists successor): pick profiles
# (Runtimes / Standard / Gaming / Technician), browse categories, search, save/load a
# selection, dry run, then install with the robust winget engine from common.ps1.
# The catalog (catalog/software.json) is embedded into dist/ by build.ps1 as $CatalogJson.
# ---------------------------------------------------------------------------

$SoftwareState = @{ Catalog = $null; Selected = $null; Upgrade = $false; DryRun = $false }

function Get-SoftwareCatalog {
    if ($SoftwareState.Catalog) { return $SoftwareState.Catalog }
    $json = $CatalogJson
    if (-not $json) {
        # running from src/ (development, tests): read the repo file
        $file = Join-Path $PSScriptRoot '..\..\catalog\software.json'
        if (-not (Test-Path -LiteralPath $file)) { throw "Catalog not found: $file" }
        $json = Get-Content -LiteralPath $file -Raw -Encoding UTF8
    }
    try { $cat = $json | ConvertFrom-Json } catch { throw "Catalog is not valid JSON: $($_.Exception.Message)" }
    foreach ($field in 'apps', 'categories', 'profiles') {
        if (-not ($cat.PSObject.Properties.Name -contains $field)) { throw "Catalog has no '$field' field." }
    }
    $dupes = @($cat.apps | Group-Object key | Where-Object Count -gt 1)
    if ($dupes.Count -gt 0) { throw ("Duplicate keys in catalog: {0}" -f (($dupes | Select-Object -First 5).Name -join ', ')) }
    $SoftwareState.Catalog = $cat
    return $cat
}

function Get-SoftwareSelection {
    if (-not $SoftwareState.Selected) {
        $SoftwareState.Selected = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
    }
    return ,$SoftwareState.Selected   # comma: do not enumerate the HashSet on output
}

function Get-SoftwareProfileNames {
    param($Catalog)
    return @($Catalog.profiles.PSObject.Properties | ForEach-Object Name)
}

function Add-SoftwareProfile {
    param($Catalog, [Parameter(Mandatory)][string]$Name)
    $sel = Get-SoftwareSelection
    $p = $Catalog.profiles.PSObject.Properties[$Name]
    if (-not $p) { throw "Unknown profile '$Name'. Available: $((Get-SoftwareProfileNames $Catalog) -join ', ')" }
    foreach ($k in $p.Value.apps) { [void]$sel.Add($k) }
}

function Expand-NumberList {
    # "1 3 5-9" -> 1,3,5,6,7,8,9 (bounded by 1..Max)
    param([string]$Text, [int]$Max)
    $out = New-Object 'System.Collections.Generic.List[int]'
    foreach ($part in ($Text -split '[,\s]+' | Where-Object { $_ })) {
        if ($part -match '^(\d+)-(\d+)$') {
            $a = [int]$Matches[1]; $b = [int]$Matches[2]
            if ($a -gt $b) { $t = $a; $a = $b; $b = $t }
            for ($i = $a; $i -le $b; $i++) { if ($i -ge 1 -and $i -le $Max) { $out.Add($i) } }
        } elseif ($part -match '^\d+$') {
            $i = [int]$part
            if ($i -ge 1 -and $i -le $Max) { $out.Add($i) }
        }
    }
    return ,$out
}

function Show-NumberedList {
    # numbered list with [x] marks, two columns from 24 entries on
    param($Items, $Selected)
    $n = $Items.Count
    $cols = if ($n -gt 24) { 2 } else { 1 }
    $rows = [math]::Ceiling($n / $cols)
    $width = 34
    for ($r = 0; $r -lt $rows; $r++) {
        $line = ''
        for ($c = 0; $c -lt $cols; $c++) {
            $i = $r + ($c * $rows)
            if ($i -ge $n) { continue }
            $e = $Items[$i]
            $mark = if ($Selected.Contains($e.key)) { 'x' } else { ' ' }
            $text = $e.name
            if ($text.Length -gt $width) { $text = $text.Substring(0, $width - 1) + '.' }
            $line += ('  [{0}] {1,3}. {2,-' + $width + '}') -f $mark, ($i + 1), $text
        }
        Write-Host $line
    }
}

function Show-SoftwareCategory {
    param($Catalog, [string]$Category)
    $sel = Get-SoftwareSelection
    $items = @($Catalog.apps | Where-Object { $_.category -eq $Category } | Sort-Object name)
    while ($true) {
        Clear-Host
        $chosen = @($items | Where-Object { $sel.Contains($_.key) }).Count
        Write-Title ("{0}  ({1} packages, {2} selected)" -f $Category, $items.Count, $chosen)
        Write-Host ''
        Show-NumberedList -Items $items -Selected $sel
        Write-Host ''
        Write-Host '  Toggle numbers (e.g. 1 4 7-9)   [a] all   [n] none   [i <nr>] info   [Enter] back' -ForegroundColor DarkGray
        $e = Read-MenuLine
        if ($e -eq '') { return }
        if ($e -eq 'a') { foreach ($x in $items) { [void]$sel.Add($x.key) }; continue }
        if ($e -eq 'n') { foreach ($x in $items) { [void]$sel.Remove($x.key) }; continue }
        if ($e -match '^i\s+(\d+)$') {
            $i = [int]$Matches[1]
            if ($i -ge 1 -and $i -le $items.Count) {
                $a = $items[$i - 1]
                Write-Host ''
                Write-Host ("  {0}" -f $a.name) -ForegroundColor White
                Write-Host ("  winget id : {0}" -f $(if ($a.type -eq 'feature') { "Windows feature $($a.feature)" } else { $a.id })) -ForegroundColor DarkGray
                if ($a.link) { Write-Host ("  website   : {0}" -f $a.link) -ForegroundColor DarkGray }
                if ($a.info) { Write-Host ("  info      : {0}" -f $a.info) -ForegroundColor DarkGray }
                Write-Host ''
                $null = Read-MenuLine '  Enter to continue'
            }
            continue
        }
        foreach ($i in (Expand-NumberList -Text $e -Max $items.Count)) {
            $k = $items[$i - 1].key
            if ($sel.Contains($k)) { [void]$sel.Remove($k) } else { [void]$sel.Add($k) }
        }
    }
}

function Show-SoftwareSearch {
    param($Catalog)
    $sel = Get-SoftwareSelection
    $term = Read-MenuLine '  Search'
    if (-not $term) { return }
    $hits = @($Catalog.apps | Where-Object { $_.name -like "*$term*" -or $_.id -like "*$term*" -or $_.key -like "*$term*" } | Sort-Object category, name)
    if ($hits.Count -eq 0) {
        Write-Warn "Nothing found for '$term'."
        $null = Read-MenuLine '  Enter to continue'
        return
    }
    while ($true) {
        Clear-Host
        Write-Title ("Search '{0}' - {1} hits" -f $term, $hits.Count)
        Write-Host ''
        for ($i = 0; $i -lt $hits.Count; $i++) {
            $e = $hits[$i]
            $mark = if ($sel.Contains($e.key)) { 'x' } else { ' ' }
            Write-Host ('  [{0}] {1,3}. {2,-36} {3}' -f $mark, ($i + 1), $e.name, $e.category)
        }
        Write-Host ''
        Write-Host '  Toggle numbers   [a] all   [Enter] back' -ForegroundColor DarkGray
        $e = Read-MenuLine
        if ($e -eq '') { return }
        if ($e -eq 'a') { foreach ($x in $hits) { [void]$sel.Add($x.key) }; continue }
        foreach ($i in (Expand-NumberList -Text $e -Max $hits.Count)) {
            $k = $hits[$i - 1].key
            if ($sel.Contains($k)) { [void]$sel.Remove($k) } else { [void]$sel.Add($k) }
        }
    }
}

function Get-SelectionFolder {
    $dir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'win-toolbox'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Save-SoftwareSelection {
    $sel = Get-SoftwareSelection
    $name = Read-MenuLine '  File name (Enter = selection.json)'
    if (-not $name) { $name = 'selection.json' }
    if ($name -notlike '*.json') { $name += '.json' }
    $path = if ([IO.Path]::IsPathRooted($name)) { $name } else { Join-Path (Get-SelectionFolder) $name }
    if ((Test-Path -LiteralPath $path) -and -not (Confirm-Action "  $([IO.Path]::GetFileName($path)) exists. Overwrite?")) { return }
    try {
        [pscustomobject]@{ created = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); host = $env:COMPUTERNAME; apps = @($sel) } |
            ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding UTF8
        Write-Ok "Saved: $path"
    } catch { Write-Fail "Save failed: $($_.Exception.Message)" }
    $null = Read-MenuLine '  Enter to continue'
}

function Import-SoftwareSelection {
    <# Loads a saved selection from a local file or a URL (e.g. a gist raw link). #>
    param($Catalog, [string]$Source)
    $sel = Get-SoftwareSelection
    if (-not $Source) {
        $files = @(Get-ChildItem -LiteralPath (Get-SelectionFolder) -Filter '*.json' -ErrorAction SilentlyContinue)
        for ($i = 0; $i -lt $files.Count; $i++) { Write-Host ('    [{0}] {1}' -f ($i + 1), $files[$i].Name) }
        if ($files.Count -eq 0) { Write-Host ('    (no saved selections in {0})' -f (Get-SelectionFolder)) -ForegroundColor DarkGray }
        $Source = Read-MenuLine '  Number, path or URL'
        if ($Source -match '^\d+$' -and [int]$Source -ge 1 -and [int]$Source -le $files.Count) { $Source = $files[[int]$Source - 1].FullName }
        if (-not $Source) { return }
    }
    try {
        $json = if ($Source -match '^https?://') { Invoke-RestMethod -Uri $Source -UseBasicParsing } else { Get-Content -LiteralPath $Source -Raw -Encoding UTF8 }
        $obj = if ($json -is [string]) { $json | ConvertFrom-Json } else { $json }
        if (-not ($obj.PSObject.Properties.Name -contains 'apps')) { throw 'selection file has no "apps" field (expected {"apps":["7zip","vlc"]})' }
        $known = @{}; foreach ($a in $Catalog.apps) { $known[$a.key] = $true }
        $unknown = @($obj.apps | Where-Object { -not $known.ContainsKey($_) })
        $sel.Clear()
        foreach ($k in $obj.apps) { if ($known.ContainsKey($k)) { [void]$sel.Add($k) } }
        Write-Ok ("{0} packages loaded." -f $sel.Count)
        if ($unknown.Count -gt 0) { Write-Warn ("Ignored unknown keys: {0}" -f ($unknown -join ', ')) }
    } catch { Write-Fail "Load failed: $($_.Exception.Message)" }
    $null = Read-MenuLine '  Enter to continue'
}

function Show-SoftwareSelection {
    param($Catalog)
    $sel = Get-SoftwareSelection
    Clear-Host
    Write-Title ("Selected: {0} packages" -f $sel.Count)
    $Catalog.apps | Where-Object { $sel.Contains($_.key) } | Sort-Object category, name |
        Format-Table @{ L = 'Category'; E = { $_.category } }, @{ L = 'Name'; E = { $_.name } }, @{ L = 'winget id'; E = { $_.id } } -AutoSize |
        Out-String -Width 120 | Write-Host
    $null = Read-MenuLine '  Enter to continue'
}

function Show-SoftwareMenu {
    <# Returns $true when the user wants to install the current selection, $false to go back. #>
    param($Catalog)
    $sel = Get-SoftwareSelection
    $profiles = Get-SoftwareProfileNames $Catalog
    $cats = @($Catalog.categories)
    while ($true) {
        Clear-Host
        Write-Title 'Software Setup'
        Write-Host ("   Catalog  : {0} packages, updated {1}" -f @($Catalog.apps).Count, $Catalog.updated) -ForegroundColor DarkGray
        Write-Host ("   Selected : {0} packages" -f $sel.Count) -ForegroundColor $(if ($sel.Count) { 'Green' } else { 'Yellow' })
        Write-Host ("   Mode     : {0}{1}" -f $(if ($SoftwareState.Upgrade) { 'install missing + upgrade present' } else { 'install missing only' }),
                                              $(if ($SoftwareState.DryRun) { '   [DRY RUN - nothing is installed]' } else { '' })) -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '   Profiles (add to selection):'
        for ($i = 0; $i -lt $profiles.Count; $i++) {
            $p = $Catalog.profiles.PSObject.Properties[$profiles[$i]].Value
            Write-Host ('     [{0,2}] {1,-12} {2,3} pkgs   {3}' -f ($i + 1), $profiles[$i], @($p.apps).Count, $p.description)
        }
        Write-Host ''
        Write-Host '   Categories (browse and toggle single packages):'
        for ($i = 0; $i -lt $cats.Count; $i++) {
            $all = @($Catalog.apps | Where-Object { $_.category -eq $cats[$i] })
            $chosen = @($all | Where-Object { $sel.Contains($_.key) }).Count
            Write-Host ('     [{0,2}] {1,-22} {2,3} pkgs{3}' -f ($profiles.Count + $i + 1), $cats[$i], $all.Count, $(if ($chosen) { "   ($chosen selected)" } else { '' }))
        }
        Write-Host ''
        Write-Host '     [s] search      [v] view selection   [x] clear selection'
        Write-Host '     [u] toggle upgrade mode              [d] toggle dry run'
        Write-Host '     [l] load selection (file/URL)        [w] save selection'
        Write-Host ''
        Write-Host '     [Enter] install selection            [q] back' -ForegroundColor Green
        Write-Host ''
        $e = (Read-MenuLine '  Choice').ToLower()

        if ($e -eq '') {
            if ($sel.Count -eq 0) { Write-Warn 'Nothing selected.'; Start-Sleep -Seconds 1; continue }
            return $true
        }
        switch -Regex ($e) {
            '^q$' { return $false }
            '^s$' { Show-SoftwareSearch -Catalog $Catalog; break }
            '^v$' { Show-SoftwareSelection -Catalog $Catalog; break }
            '^x$' { $sel.Clear(); break }
            '^u$' { $SoftwareState.Upgrade = -not $SoftwareState.Upgrade; break }
            '^d$' { $SoftwareState.DryRun = -not $SoftwareState.DryRun; break }
            '^l$' { Import-SoftwareSelection -Catalog $Catalog; break }
            '^w$' { Save-SoftwareSelection; break }
            '^\d+$' {
                $i = [int]$e
                if ($i -ge 1 -and $i -le $profiles.Count) { Add-SoftwareProfile -Catalog $Catalog -Name $profiles[$i - 1] }
                elseif ($i -gt $profiles.Count -and $i -le ($profiles.Count + $cats.Count)) { Show-SoftwareCategory -Catalog $Catalog -Category $cats[$i - $profiles.Count - 1] }
                break
            }
        }
    }
}

function Invoke-SoftwareInstall {
    <# Installs the current selection; returns the result objects. #>
    param($Catalog)
    $sel = Get-SoftwareSelection
    $list = @($Catalog.apps | Where-Object { $sel.Contains($_.key) } |
              Sort-Object @{ E = { if ($_.category -eq 'Runtimes') { 0 } else { 1 } } }, category, name)
    if ($list.Count -eq 0) { Write-Warn 'Nothing selected.'; return @() }
    if (-not (Test-IsAdmin)) { throw 'Administrator rights are required to install software.' }

    $log = Start-Log -Name 'software-setup'
    Write-Title ("Installing {0} packages{1}" -f $list.Count, $(if ($SoftwareState.DryRun) { ' (dry run)' } else { '' }))
    Write-LogLine ("selection: {0}" -f (($list | ForEach-Object key) -join ' '))

    if (@($list | Where-Object { $_.type -eq 'winget' }).Count -gt 0) {
        $null = Initialize-WinGet
        if (-not $SoftwareState.DryRun) { Update-WinGetSources }
    }
    $results = New-Object 'System.Collections.Generic.List[object]'
    $start = Get-Date
    $n = 0
    foreach ($app in $list) {
        $n++
        Write-Host ("`n  [{0}/{1}] {2}" -f $n, $list.Count, $app.category) -ForegroundColor DarkGray
        try {
            if ($app.type -eq 'feature') { $r = Install-WindowsFeatureItem -FeatureName $app.feature -Name $app.name -DryRun:$SoftwareState.DryRun }
            else { $r = Install-WinGetPackage -Id $app.id -Name $app.name -Upgrade:$SoftwareState.Upgrade -DryRun:$SoftwareState.DryRun }
        } catch {
            Write-Fail ("{0} - unexpected error: {1}" -f $app.name, $_.Exception.Message)
            $r = [pscustomobject]@{ Status = 'Failed'; Code = -997; Note = $_.Exception.Message; Variant = '' }
        }
        $results.Add([pscustomobject]@{ Category = $app.category; Key = $app.key; Name = $app.name; Id = $app.id; Status = $r.Status; Code = $r.Code; Note = $r.Note; Variant = $r.Variant })
    }
    Write-SoftwareReport -Results $results -Duration ((Get-Date) - $start) -LogPath $log
    return ,$results
}

function Write-SoftwareReport {
    param($Results, [timespan]$Duration, [string]$LogPath)
    Write-Title 'Summary'
    foreach ($g in ($Results | Group-Object Status | Sort-Object Name)) {
        $color = switch ($g.Name) { 'Failed' { 'Red' } 'Present' { 'DarkGray' } default { 'Green' } }
        Write-Host ('   {0,-10} {1,3}' -f $g.Name, $g.Count) -ForegroundColor $color
    }
    $userScope = @($Results | Where-Object { $_.Variant -and $_.Variant -ne 'machine scope' -and $_.Variant -ne 'msstore' })
    if ($userScope.Count -gt 0) {
        Write-Host ''
        Write-Host '   Installed without enforced machine scope (package does not support it):' -ForegroundColor Yellow
        foreach ($u in $userScope) { Write-Host ('     - {0}' -f $u.Name) -ForegroundColor Yellow }
        Write-Host '     Whether they apply to all users is up to the installer.' -ForegroundColor DarkGray
    }
    $failed = @($Results | Where-Object Status -eq 'Failed')
    if ($failed.Count -gt 0) {
        Write-Host ''
        Write-Host '   Not installed:' -ForegroundColor Red
        foreach ($f in $failed) { Write-Host ('     - {0,-34} {1}' -f $f.Name, $f.Note) -ForegroundColor Red }
        Write-Host '   Retry single packages with:' -ForegroundColor DarkGray
        foreach ($f in ($failed | Where-Object Id | Select-Object -First 5)) { Write-Host ('     winget install --exact --id {0}' -f $f.Id) -ForegroundColor DarkGray }
    }
    if (@($Results | Where-Object { $_.Note -like '*reboot*' }).Count -gt 0) {
        Write-Host ''
        Write-Host '   At least one package needs a reboot to take effect.' -ForegroundColor Yellow
    }
    if ($LogPath) {
        $csv = [IO.Path]::ChangeExtension($LogPath, 'csv')
        try {
            $Results | Select-Object @{ L = 'Timestamp'; E = { Get-Date -Format 'yyyy-MM-dd HH:mm:ss' } }, @{ L = 'Host'; E = { $env:COMPUTERNAME } },
                Category, Name, Id, Status, Code, Variant, Note |
                Export-Csv -LiteralPath $csv -NoTypeInformation -Delimiter ';' -Encoding UTF8
            Write-Host ''
            Write-Host ("   Report : {0}" -f $csv) -ForegroundColor DarkGray
        } catch { Write-Warn "CSV report could not be written: $($_.Exception.Message)" }
        Write-Host ("   Log    : {0}" -f $LogPath) -ForegroundColor DarkGray
    }
    Write-Host ("   Took   : {0:hh\:mm\:ss}" -f $Duration) -ForegroundColor DarkGray
}

function Invoke-SoftwareSetup {
    <#
    .SYNOPSIS
        Menu-driven software installation from the embedded catalog (profiles, categories, search).
    .PARAMETER ProfileName
        Pre-select a profile (Runtimes, Standard, Gaming, Technician).
    #>
    param([string]$ProfileName)
    $cat = Get-SoftwareCatalog
    if ($ProfileName) { Add-SoftwareProfile -Catalog $cat -Name $ProfileName }
    while (Show-SoftwareMenu -Catalog $cat) {
        $null = Invoke-SoftwareInstall -Catalog $cat
        Wait-AnyKey 'Press any key to return to the Software Setup menu...'
    }
}
