# ---------------------------------------------------------------------------
# tools/inventory.ps1 - hardware, OS and software inventory -> CSV.
# English port of Inventar-Windows.ps1 (technician stick). The CSV SCHEMA STAYS GERMAN on
# purpose (Zeitstempel;Hostname;Kategorie;Feld;Wert, Inventar_Uebersicht.csv columns,
# UTF-8 BOM + CRLF): it is shared with inventar-linux.sh and existing collections. Only the
# console UI is English. Do not rename fields/values in the data without changing the Linux twin.
# ---------------------------------------------------------------------------

$InventoryState = @{
    OutputMode = 'Desktop'      # Desktop | CurrentDir | Custom
    OutputPath = ''
    Delimiter  = ';'
    Comment    = ''
    Summary    = $true
    Software   = 'all'          # all | noupdates | none
    Detail     = $false
}

function Get-InventoryOutputPath {
    switch ($InventoryState.OutputMode) {
        'CurrentDir' { return (Get-Location).Path }
        'Custom'     { if ($InventoryState.OutputPath) { return $InventoryState.OutputPath } }
    }
    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not $desktop) { $desktop = (Get-Location).Path }
    return $desktop
}

function Select-FolderDialog {
    # Folder picker seam (replaced by tests). Returns path or $null.
    param([string]$Description = 'Select the output folder')
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = $Description
        $dlg.ShowNewFolderButton = $true
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    } catch { Write-Warn "Folder dialog not available: $($_.Exception.Message)" }
    return $null
}

function Show-InventoryMenu {
    <# Returns $true to start, $false to go back. #>
    while ($true) {
        Clear-Host
        Write-Title 'Inventory'
        Write-Host '   Collects hardware, BIOS/TPM, OS, CPU, RAM, disks, GPU, monitors, network, battery and' -ForegroundColor DarkGray
        Write-Host '   installed software into CSV files (German schema, compatible with inventar-linux.sh).' -ForegroundColor DarkGray
        Write-Host ''
        $modeText = switch ($InventoryState.OutputMode) { 'Desktop' { 'Desktop' } 'CurrentDir' { 'current directory' } 'Custom' { 'custom folder' } }
        Write-Host ("   [1] Output folder   : {0}  ({1})" -f (Get-InventoryOutputPath), $modeText)
        Write-Host ("   [2] CSV delimiter   : {0}" -f $(if ($InventoryState.Delimiter -eq "`t") { 'TAB' } else { $InventoryState.Delimiter }))
        Write-Host ("   [3] Comment         : {0}" -f $(if ($InventoryState.Comment) { $InventoryState.Comment } else { '(none)' }))
        Write-Host ("   [4] Append overview : {0}" -f $(if ($InventoryState.Summary) { 'yes (Inventar_Uebersicht.csv)' } else { 'no' }))
        Write-Host ("   [5] Rights          : {0}" -f $(if (Test-IsAdmin) { 'administrator' } else { 'standard user - [5] relaunches elevated (TPM, battery, RAM modules need admin)' }))
        Write-Host ("   [6] Software        : {0}" -f $(switch ($InventoryState.Software) { 'all' { 'programs, store apps and Windows updates' } 'noupdates' { 'programs and store apps, no Windows updates' } 'none' { 'not collected' } }))
        Write-Host ("   [7] Software detail : {0}" -f $(if ($InventoryState.Detail) { 'yes - every program as a row in the detail CSV' } else { 'no - counts only' }))
        Write-Host ''
        Write-Host '   [Enter] start inventory        [q] back' -ForegroundColor Green
        Write-Host ''
        $e = (Read-MenuLine '  Choice').ToLower()
        switch ($e) {
            ''  { return $true }
            's' { return $true }
            'q' { return $false }
            '1' {
                Write-Host ''
                Write-Host '     [1] Desktop   [2] current directory   [3] pick a folder'
                $m = Read-MenuLine '  Output folder'
                switch ($m) {
                    '1' { $InventoryState.OutputMode = 'Desktop' }
                    '2' { $InventoryState.OutputMode = 'CurrentDir' }
                    '3' { $p = Select-FolderDialog; if ($p) { $InventoryState.OutputMode = 'Custom'; $InventoryState.OutputPath = $p } }
                }
            }
            '2' {
                $d = Read-MenuLine "  Delimiter - ';' , ',' or 'TAB' (Enter = unchanged)"
                if ($d) {
                    if ($d.ToUpper() -eq 'TAB') { $InventoryState.Delimiter = "`t" }
                    elseif ($d.Length -eq 1) { $InventoryState.Delimiter = $d }
                    else { Write-Warn 'The delimiter must be exactly one character.'; Start-Sleep -Seconds 1 }
                }
            }
            '3' { $InventoryState.Comment = Read-MenuLine '  Comment (e.g. loan device company XY, invoice 1234)' }
            '4' { $InventoryState.Summary = -not $InventoryState.Summary }
            '5' {
                if (Test-IsAdmin) { Write-Warn 'Already running as administrator.'; Start-Sleep -Seconds 1 }
                elseif (Invoke-Elevated -SelfUrl $SelfUrl) { Write-Warn 'Elevated window started - settings start fresh there.'; Start-Sleep -Seconds 2; return $false }
            }
            '6' {
                $InventoryState.Software = switch ($InventoryState.Software) { 'all' { 'noupdates' } 'noupdates' { 'none' } default { 'all' } }
            }
            '7' { $InventoryState.Detail = -not $InventoryState.Detail }
        }
    }
}

function Update-CsvHeader {
    <#
        Appended CSVs (overview, software) would silently lose new columns with Export-Csv -Append -Force.
        Lifts an existing file to the new column set once: old rows stay, new fields stay empty,
        extra columns written by the other tool are preserved. Port of Update-UebersichtKopf.
    #>
    param([string]$Path, [string[]]$Columns, [string]$Delimiter, [string]$Encoding, [string]$Label = 'overview')
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $old = $null
    try { $old = @(Import-Csv -LiteralPath $Path -Delimiter $Delimiter -ErrorAction Stop) } catch {
        Write-Fail "$Label`: $Path is not readable - new columns cannot be added; the next row is appended without them."
        return
    }
    if ($old.Count -eq 0) {
        try {
            $head = Get-Content -LiteralPath $Path -TotalCount 1 -ErrorAction Stop
            $want = ($Columns | ForEach-Object { '"{0}"' -f $_ }) -join $Delimiter
            if ($head -and $head.Trim() -ne $want) { Remove-Item -LiteralPath $Path -Force -ErrorAction Stop; Write-Warn "$Label`: outdated header without rows removed, file is recreated." }
        } catch { $null = $_ }
        return
    }
    $have = @($old[0].PSObject.Properties.Name)
    if ($have -notcontains 'Hostname') {
        Write-Fail "$Label`: no 'Hostname' column in $Path - probably written with another delimiter than '$Delimiter'. File left untouched."
        return
    }
    $missing = @($Columns | Where-Object { $have -notcontains $_ })
    if ($missing.Count -eq 0) { return }
    $target = @($Columns) + @($have | Where-Object { $Columns -notcontains $_ })
    $backup = $Path -replace '\.csv$', ("_vor-Erweiterung_{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    try { Copy-Item -LiteralPath $Path -Destination $backup -Force -ErrorAction Stop } catch { Write-Fail "$Label`: backup failed - file left untouched."; return }
    $new = foreach ($row in $old) {
        $o = [ordered]@{}
        foreach ($c in $target) { $o[$c] = if ($have -contains $c) { $row.$c } else { '' } }
        [pscustomobject]$o
    }
    try { $new | Export-Csv -Path $Path -Delimiter $Delimiter -NoTypeInformation -Encoding $Encoding -ErrorAction Stop }
    catch { Write-Fail "$Label`: could not be rewritten: $($_.Exception.Message) - original is in $backup"; return }
    Write-Warn ("{0}: extended with new columns: {1} (backup: {2})" -f $Label, ($missing -join ', '), $backup)
}

function Invoke-InventoryRun {
    <#
    .SYNOPSIS
        Collects the inventory and writes Inventar_<host>_<stamp>.csv (+ Inventar_Software.csv,
        Inventar_Uebersicht.csv). Returns @{ Detail; Software; Overview; Rows; WriteErrors }.
    #>
    param(
        [string]$OutputPath = (Get-InventoryOutputPath),
        [string]$Delimiter = $InventoryState.Delimiter,
        [string]$Comment = $InventoryState.Comment,
        [bool]$Summary = $InventoryState.Summary,
        [string]$Software = $InventoryState.Software,
        [bool]$Detail = $InventoryState.Detail
    )
    $ErrorActionPreference = 'SilentlyContinue'   # collection must never abort on a missing CIM class
    $Zeitstempel   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $Aufnahmedatum = Get-Date -Format 'dd.MM.yyyy'
    $Dateistempel  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $Rechnername   = $env:COMPUTERNAME
    if (-not $Rechnername) { $Rechnername = [Environment]::MachineName }
    $Zeilen  = New-Object System.Collections.Generic.List[object]
    $Kurz    = [ordered]@{}
    $SoftwareListe   = New-Object System.Collections.Generic.List[object]
    $SoftwareGesehen = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
    $IstAdmin = Test-IsAdmin

    function Add-Row {
        param([string]$Kategorie, [string]$Feld, $Wert)
        if ($null -eq $Wert) { return }
        $v = (($Wert | ForEach-Object { "$_" }) -join ', ').Trim()
        if ([string]::IsNullOrWhiteSpace($v)) { return }
        if ($v -match '^(To Be Filled By O\.E\.M\.|Default string|System manufacturer|Not Specified|None|Unknown)$') { return }
        $Zeilen.Add([pscustomobject]@{ Zeitstempel = $Zeitstempel; Hostname = $Rechnername; Kategorie = $Kategorie; Feld = $Feld; Wert = $v })
    }
    function Invoke-Section { param([string]$Name, [scriptblock]$Body) try { & $Body } catch { Add-Row 'Fehler' $Name $_.Exception.Message } }
    function ConvertFrom-WmiCharArray { param($Array) if (-not $Array) { return '' }; (($Array | Where-Object { $_ -ne 0 }) | ForEach-Object { [char]$_ }) -join '' }
    function Format-GB { param([double]$Bytes) if ($Bytes -le 0) { return '' }; '{0:N1}' -f ($Bytes / 1GB) }
    function Add-Software {
        param([string]$Typ, [string]$Name, [string]$Version, [string]$Hersteller, $Datum, [string]$Quelle)
        if ([string]::IsNullOrWhiteSpace($Name)) { return }
        $n = ($Name -replace '\s+', ' ').Trim(); $v = ("$Version" -replace '\s+', ' ').Trim(); $h = ("$Hersteller" -replace '\s+', ' ').Trim()
        if ($h -match 'CN=([^,]+)') { $h = $Matches[1].Trim() }
        if (-not $SoftwareGesehen.Add("$Typ|$n|$v")) { return }
        $d = ''
        if ($Datum) { try { $d = (Get-Date $Datum -Format 'yyyy-MM-dd') } catch { $d = '' } }
        $SoftwareListe.Add([pscustomobject]@{ Typ = $Typ; Name = $n; Version = $v; Hersteller = $h; Installiert = $d; Quelle = $Quelle })
    }
    function Get-InstallDatum {
        param($Eintrag)
        if ($Eintrag.InstallDate -match '^\d{8}$') { try { return [datetime]::ParseExact($Eintrag.InstallDate, 'yyyyMMdd', $null) } catch { $null = $_ } }
        if ($Eintrag.InstallLocation) {
            try {
                $ort = "$($Eintrag.InstallLocation)".Trim('"').TrimEnd('\')
                if ($ort -and (Test-Path -LiteralPath $ort)) { return (Get-Item -LiteralPath $ort -ErrorAction Stop).CreationTime }
            } catch { $null = $_ }
        }
        return $null
    }

    Write-Step 'Collecting inventory...'
    Add-Row 'Erfassung' 'Skriptversion'       "win-toolbox $ToolboxVersion"
    Add-Row 'Erfassung' 'Aufnahmedatum'       $Aufnahmedatum
    Add-Row 'Erfassung' 'Erfasst am'          $Zeitstempel
    Add-Row 'Erfassung' 'Erfasst von'         "$env:USERDOMAIN\$env:USERNAME"
    Add-Row 'Erfassung' 'Administratorrechte' $(if ($IstAdmin) { 'Ja' } else { 'Nein (einige Felder unvollstaendig)' })
    if ($Comment) { Add-Row 'Erfassung' 'Kommentar' $Comment }

    Invoke-Section 'System' {
        $cs = Get-CimInstance Win32_ComputerSystem; $bios = Get-CimInstance Win32_BIOS
        $prod = Get-CimInstance Win32_ComputerSystemProduct; $encl = Get-CimInstance Win32_SystemEnclosure
        $chassisMap = @{ 1='Other';2='Unbekannt';3='Desktop';4='Low Profile Desktop';5='Pizza Box';6='Mini Tower';7='Tower';8='Portable';9='Laptop';10='Notebook';11='Handheld';12='Docking Station';13='All in One';14='Sub Notebook';15='Space-Saving';16='Lunch Box';17='Main System Chassis';18='Expansion Chassis';21='Peripheral';23='Rack Mount';30='Tablet';31='Convertible';32='Detachable' }
        $formfaktor = ($encl.ChassisTypes | ForEach-Object { if ($chassisMap[[int]$_]) { $chassisMap[[int]$_] } else { "Typ $_" } }) -join ', '
        Add-Row 'System' 'Hostname' $Rechnername; Add-Row 'System' 'Hersteller' $cs.Manufacturer; Add-Row 'System' 'Modell' $cs.Model
        Add-Row 'System' 'Seriennummer' $bios.SerialNumber; Add-Row 'System' 'Asset-Tag' $encl.SMBIOSAssetTag; Add-Row 'System' 'UUID' $prod.UUID
        Add-Row 'System' 'Formfaktor' $formfaktor; Add-Row 'System' 'Domaene/Workgroup' $cs.Domain
        Add-Row 'System' 'Angemeldeter Benutzer' $cs.UserName; Add-Row 'System' 'Systemtyp' $cs.SystemType
        $Kurz['Hersteller'] = $cs.Manufacturer; $Kurz['Modell'] = $cs.Model; $Kurz['Seriennummer'] = $bios.SerialNumber
        $Kurz['AssetTag'] = $encl.SMBIOSAssetTag; $Kurz['Formfaktor'] = $formfaktor
    }
    Invoke-Section 'BIOS' {
        $bb = Get-CimInstance Win32_BaseBoard; $bios = Get-CimInstance Win32_BIOS
        Add-Row 'Mainboard' 'Hersteller' $bb.Manufacturer; Add-Row 'Mainboard' 'Modell' $bb.Product; Add-Row 'Mainboard' 'Seriennummer' $bb.SerialNumber
        Add-Row 'BIOS' 'Hersteller' $bios.Manufacturer
        Add-Row 'BIOS' 'Version' $(if ($bios.SMBIOSBIOSVersion) { $bios.SMBIOSBIOSVersion } else { $bios.Version })
        if ($bios.ReleaseDate) { Add-Row 'BIOS' 'Datum' (Get-Date $bios.ReleaseDate -Format 'yyyy-MM-dd') }
        $fw = if ((Get-CimInstance Win32_DiskPartition | Where-Object { $_.Type -like '*GPT*' })) { 'UEFI (vermutlich)' } else { '' }
        if ($env:firmware_type) { $fw = $env:firmware_type }
        Add-Row 'BIOS' 'Firmware-Modus' $fw
        $sb = try { Confirm-SecureBootUEFI } catch { $null }
        if ($null -ne $sb) { Add-Row 'BIOS' 'Secure Boot' $(if ($sb) { 'Aktiv' } else { 'Inaktiv' }) }
        $tpm = Get-CimInstance -Namespace 'root\cimv2\security\microsofttpm' -ClassName Win32_Tpm
        if ($tpm) { Add-Row 'BIOS' 'TPM vorhanden' 'Ja'; Add-Row 'BIOS' 'TPM Version' $tpm.SpecVersion; Add-Row 'BIOS' 'TPM aktiviert' $(if ($tpm.IsEnabled_InitialValue) { 'Ja' } else { 'Nein' }) }
        $Kurz['BIOS_Version'] = $bios.SMBIOSBIOSVersion
    }
    Invoke-Section 'Betriebssystem' {
        $os = Get-CimInstance Win32_OperatingSystem; $dv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        Add-Row 'Betriebssystem' 'Name' $os.Caption; Add-Row 'Betriebssystem' 'Edition/Release' $dv.DisplayVersion; Add-Row 'Betriebssystem' 'Version' $os.Version
        Add-Row 'Betriebssystem' 'Build' "$($dv.CurrentBuild).$($dv.UBR)"; Add-Row 'Betriebssystem' 'Architektur' $os.OSArchitecture; Add-Row 'Betriebssystem' 'Sprache' (Get-Culture).Name
        if ($os.InstallDate) { Add-Row 'Betriebssystem' 'Installiert am' (Get-Date $os.InstallDate -Format 'yyyy-MM-dd') }
        if ($os.LastBootUpTime) { Add-Row 'Betriebssystem' 'Letzter Start' (Get-Date $os.LastBootUpTime -Format 'yyyy-MM-dd HH:mm') }
        Add-Row 'Betriebssystem' 'PowerShell-Version' $PSVersionTable.PSVersion.ToString()
        $lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f'" | Select-Object -First 1
        if ($lic) { Add-Row 'Betriebssystem' 'Lizenzstatus' $(if ($lic.LicenseStatus -eq 1) { 'Aktiviert' } else { "Status-Code $($lic.LicenseStatus)" }) }
        $Kurz['OS'] = $os.Caption; $Kurz['OSVersion'] = "$($dv.DisplayVersion) / $($dv.CurrentBuild).$($dv.UBR)"
    }
    Invoke-Section 'CPU' {
        $cpus = @(Get-CimInstance Win32_Processor); $i = 0
        foreach ($cpu in $cpus) {
            $i++; $p = if ($cpus.Count -gt 1) { "CPU $i " } else { '' }
            Add-Row 'CPU' "${p}Bezeichnung" $cpu.Name; Add-Row 'CPU' "${p}Hersteller" $cpu.Manufacturer; Add-Row 'CPU' "${p}Kerne" $cpu.NumberOfCores
            Add-Row 'CPU' "${p}Logische Kerne" $cpu.NumberOfLogicalProcessors; Add-Row 'CPU' "${p}Basistakt (MHz)" $cpu.MaxClockSpeed
            Add-Row 'CPU' "${p}Sockel" $cpu.SocketDesignation; Add-Row 'CPU' "${p}L3-Cache (KB)" $cpu.L3CacheSize
            Add-Row 'CPU' "${p}Virtualisierung" $(if ($cpu.VirtualizationFirmwareEnabled) { 'Aktiv' } else { 'Inaktiv/unbekannt' })
            if (-not $Kurz['CPU']) { $Kurz['CPU'] = ($cpu.Name -replace '\s+', ' ').Trim(); $Kurz['CPUKerne'] = "$($cpu.NumberOfCores)C/$($cpu.NumberOfLogicalProcessors)T" }
        }
    }
    Invoke-Section 'RAM' {
        $cs = Get-CimInstance Win32_ComputerSystem; $module = @(Get-CimInstance Win32_PhysicalMemory); $array = Get-CimInstance Win32_PhysicalMemoryArray | Select-Object -First 1
        $typMap = @{ 20='DDR'; 21='DDR2'; 24='DDR3'; 26='DDR4'; 34='DDR5'; 30='LPDDR4'; 35='LPDDR5' }
        Add-Row 'RAM' 'Gesamt (GB)' (Format-GB $cs.TotalPhysicalMemory); Add-Row 'RAM' 'Belegte Slots' $module.Count
        if ($array) { Add-Row 'RAM' 'Slots gesamt' $array.MemoryDevices }
        $n = 0
        foreach ($m in $module) {
            $n++
            $typ = if ($typMap[[int]$m.SMBIOSMemoryType]) { $typMap[[int]$m.SMBIOSMemoryType] } else { $m.MemoryType }
            $slot = if ($m.DeviceLocator) { $m.DeviceLocator } else { "Modul $n" }
            Add-Row 'RAM' "$slot - Groesse (GB)" (Format-GB $m.Capacity); Add-Row 'RAM' "$slot - Typ" $typ
            Add-Row 'RAM' "$slot - Takt (MHz)" $(if ($m.ConfiguredClockSpeed) { $m.ConfiguredClockSpeed } else { $m.Speed })
            Add-Row 'RAM' "$slot - Hersteller" $m.Manufacturer; Add-Row 'RAM' "$slot - Teilenummer" ($m.PartNumber -replace '\s+$', ''); Add-Row 'RAM' "$slot - Seriennummer" $m.SerialNumber
        }
        $Kurz['RAM_GB'] = Format-GB $cs.TotalPhysicalMemory; $Kurz['RAM_Module'] = ($module | ForEach-Object { "$(Format-GB $_.Capacity)GB" }) -join '+'
    }
    Invoke-Section 'Datentraeger' {
        $phys = @(Get-PhysicalDisk); $drives = @(Get-CimInstance Win32_DiskDrive | Sort-Object Index); $kurzDisks = @()
        foreach ($d in $drives) {
            $p = "Disk $($d.Index)"; $kurzDisks += ("{0}GB {1}" -f (Format-GB $d.Size), $d.Model).Trim()
            $pd = $phys | Where-Object { $_.DeviceId -eq "$($d.Index)" } | Select-Object -First 1
            Add-Row 'Datentraeger' "$p - Modell" $d.Model; Add-Row 'Datentraeger' "$p - Seriennummer" ($d.SerialNumber -replace '\s+', '')
            Add-Row 'Datentraeger' "$p - Groesse (GB)" (Format-GB $d.Size); Add-Row 'Datentraeger' "$p - Schnittstelle" $d.InterfaceType
            if ($pd) { Add-Row 'Datentraeger' "$p - Medientyp" $pd.MediaType; Add-Row 'Datentraeger' "$p - Bustyp" $pd.BusType; Add-Row 'Datentraeger' "$p - Zustand" $pd.HealthStatus }
            Add-Row 'Datentraeger' "$p - Partitionen" $d.Partitions
        }
        $Kurz['Disks'] = $kurzDisks -join ' | '
        foreach ($v in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')) {
            Add-Row 'Volumes' "$($v.DeviceID) Label" $v.VolumeName; Add-Row 'Volumes' "$($v.DeviceID) Dateisystem" $v.FileSystem
            Add-Row 'Volumes' "$($v.DeviceID) Groesse (GB)" (Format-GB $v.Size); Add-Row 'Volumes' "$($v.DeviceID) Frei (GB)" (Format-GB $v.FreeSpace)
        }
        $bl = Get-CimInstance -Namespace 'root\cimv2\security\microsoftvolumeencryption' -ClassName Win32_EncryptableVolume
        foreach ($b in @($bl)) { $st = switch ($b.ProtectionStatus) { 0 { 'Aus' } 1 { 'Aktiv' } 2 { 'Unbekannt' } }; Add-Row 'Volumes' "$($b.DriveLetter) BitLocker" $st }
    }
    Invoke-Section 'GPU' {
        $n = 0
        foreach ($g in @(Get-CimInstance Win32_VideoController)) {
            $n++; $p = "GPU $n"
            Add-Row 'GPU' "$p - Bezeichnung" $g.Name; Add-Row 'GPU' "$p - VRAM (GB)" (Format-GB $g.AdapterRAM); Add-Row 'GPU' "$p - Treiberversion" $g.DriverVersion
            Add-Row 'GPU' "$p - Aufloesung" $(if ($g.CurrentHorizontalResolution) { "$($g.CurrentHorizontalResolution)x$($g.CurrentVerticalResolution)" })
            if (-not $Kurz['GPU']) { $Kurz['GPU'] = $g.Name }
        }
    }
    Invoke-Section 'Monitore' {
        $ids = @(Get-CimInstance -Namespace 'root\wmi' -ClassName WmiMonitorID); $n = 0
        foreach ($m in $ids) {
            $n++; $p = "Monitor $n"
            Add-Row 'Monitore' "$p - Hersteller" (ConvertFrom-WmiCharArray $m.ManufacturerName); Add-Row 'Monitore' "$p - Modell" (ConvertFrom-WmiCharArray $m.UserFriendlyName)
            Add-Row 'Monitore' "$p - Seriennummer" (ConvertFrom-WmiCharArray $m.SerialNumberID); Add-Row 'Monitore' "$p - Baujahr" $m.YearOfManufacture
        }
        Add-Row 'Monitore' 'Anzahl' $ids.Count; $Kurz['Monitore'] = $ids.Count
    }
    Invoke-Section 'Netzwerk' {
        $adapter = @(Get-CimInstance Win32_NetworkAdapter -Filter 'PhysicalAdapter=TRUE AND MACAddress IS NOT NULL')
        foreach ($a in $adapter) {
            $p = $a.NetConnectionID; if (-not $p) { $p = $a.Name }
            $cfg = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "Index=$($a.Index)"
            Add-Row 'Netzwerk' "$p - Bezeichnung" $a.Name; Add-Row 'Netzwerk' "$p - MAC" $a.MACAddress
            Add-Row 'Netzwerk' "$p - Status" $(if ($a.NetEnabled) { 'Verbunden/aktiv' } else { 'Inaktiv' })
            if ($a.Speed -and $a.Speed -lt 1e15) { Add-Row 'Netzwerk' "$p - Geschwindigkeit (Mbit/s)" ([math]::Round($a.Speed / 1MB)) }
            if ($cfg.IPAddress) { Add-Row 'Netzwerk' "$p - IP" ($cfg.IPAddress -join ', ') }
            if ($cfg.DefaultIPGateway) { Add-Row 'Netzwerk' "$p - Gateway" ($cfg.DefaultIPGateway -join ', ') }
        }
        $primaer = $adapter | Where-Object { $_.NetEnabled } | Select-Object -First 1
        if ($primaer) {
            $Kurz['MAC_Primaer'] = $primaer.MACAddress
            $cfg = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "Index=$($primaer.Index)"
            $Kurz['IP_Primaer'] = ($cfg.IPAddress | Where-Object { $_ -notmatch ':' }) -join ', '
        }
    }
    Invoke-Section 'Akku' {
        $bat = Get-CimInstance Win32_Battery | Select-Object -First 1
        if (-not $bat) { return }
        Add-Row 'Akku' 'Bezeichnung' $bat.Name; Add-Row 'Akku' 'Ladestand (%)' $bat.EstimatedChargeRemaining
        $design = (Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryStaticData | Select-Object -First 1).DesignedCapacity
        $full = (Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryFullChargedCapacity | Select-Object -First 1).FullChargedCapacity
        if ($design -and $full) {
            $health = [math]::Round(($full / $design) * 100, 1)
            Add-Row 'Akku' 'Design-Kapazitaet (mWh)' $design; Add-Row 'Akku' 'Aktuelle Kapazitaet (mWh)' $full; Add-Row 'Akku' 'Gesundheit (%)' $health
            $Kurz['Akku_Gesundheit_Prozent'] = $health
        }
    }
    Invoke-Section 'Software' {
        if ($Software -eq 'none') { return }
        Write-Step 'Collecting installed software...'
        $regPfade = @(
            @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';             Q = 'Registry HKLM' }
            @{ P = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Q = 'Registry HKLM 32-Bit' }
            @{ P = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';             Q = 'Registry HKCU' }
        )
        foreach ($hive in (Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+$' })) {
            $regPfade += @{ P = "Registry::$($hive.Name)\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"; Q = 'Registry Benutzerprofil' }
            $regPfade += @{ P = "Registry::$($hive.Name)\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"; Q = 'Registry Benutzerprofil 32-Bit' }
        }
        foreach ($rp in $regPfade) {
            if (-not (Test-Path -LiteralPath $rp.P)) { continue }
            foreach ($k in (Get-ChildItem -LiteralPath $rp.P -ErrorAction SilentlyContinue)) {
                $e = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
                if (-not $e -or -not $e.DisplayName) { continue }
                if ($e.SystemComponent -eq 1) { continue }
                if ($e.ParentKeyName) { continue }
                if ($e.ReleaseType -match 'Update|Hotfix|Security') { continue }
                Add-Software 'Programm' $e.DisplayName $e.DisplayVersion $e.Publisher (Get-InstallDatum $e) $rp.Q
            }
        }
        $appx = @()
        try { $appx = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue) } catch { $null = $_ }
        if ($appx.Count -eq 0) { try { $appx = @(Get-AppxPackage -ErrorAction SilentlyContinue) } catch { $null = $_ } }
        foreach ($a in $appx) {
            if ($a.IsFramework -or $a.IsResourcePackage) { continue }
            $d = $null
            if ($a.InstallLocation) { try { $d = (Get-Item -LiteralPath $a.InstallLocation -ErrorAction Stop).CreationTime } catch { $null = $_ } }
            Add-Software 'Store-App' $a.Name $a.Version $a.Publisher $d 'Appx'
        }
        if ($Software -ne 'noupdates') {
            foreach ($h in (Get-HotFix -ErrorAction SilentlyContinue)) {
                $q = if ($h.Description) { "Windows Update ($($h.Description))" } else { 'Windows Update' }
                Add-Software 'Windows-Update' $h.HotFixID '' 'Microsoft' $h.InstalledOn $q
            }
        }
        $programme = @($SoftwareListe | Where-Object { $_.Typ -eq 'Programm' }); $storeApps = @($SoftwareListe | Where-Object { $_.Typ -eq 'Store-App' })
        $updates = @($SoftwareListe | Where-Object { $_.Typ -eq 'Windows-Update' }); $anzahl = $programme.Count + $storeApps.Count
        Add-Row 'Software' 'Anzahl gesamt' $anzahl; Add-Row 'Software' 'Davon Programme' $programme.Count; Add-Row 'Software' 'Davon Store-Apps' $storeApps.Count
        if ($Software -ne 'noupdates') { Add-Row 'Software' 'Windows-Updates' $updates.Count }
        $mitDatum = @($programme + $storeApps | Where-Object { $_.Installiert })
        $neueste = $mitDatum | Sort-Object Installiert -Descending | Select-Object -First 1
        if ($neueste) { Add-Row 'Software' 'Zuletzt installiert' ("{0} - {1}" -f $neueste.Installiert, $neueste.Name) }
        Add-Row 'Software' 'Ohne Installationsdatum' ($anzahl - $mitDatum.Count)
        $Kurz['Software_Anzahl'] = $anzahl; $Kurz['Software_Neueste_Installation'] = ''
        if ($neueste) { $Kurz['Software_Neueste_Installation'] = $neueste.Installiert }
        if ($Detail) {
            foreach ($s in ($programme + $storeApps | Sort-Object Name)) {
                $wert = @(@($s.Version, $s.Hersteller) | Where-Object { $_ })
                if ($s.Installiert) { $wert += "installiert am $($s.Installiert)" }
                $text = $wert -join ' | '
                if (-not $text) { $text = '(keine weiteren Angaben)' }
                Add-Row 'Software' $s.Name $text
            }
        }
    }

    # ---- write ---------------------------------------------------------------
    $ErrorActionPreference = 'Stop'
    $writeErrors = 0
    function Write-InventoryCsv {
        param([Parameter(Mandatory)]$Data, [Parameter(Mandatory)][string]$Path, [switch]$Append, [string]$Label)
        try {
            if ($Append) { $Data | Export-Csv -Path $Path -Delimiter $Delimiter -NoTypeInformation -Encoding $enc -Append -Force -ErrorAction Stop }
            else { $Data | Export-Csv -Path $Path -Delimiter $Delimiter -NoTypeInformation -Encoding $enc -ErrorAction Stop }
            if (-not (Test-Path -LiteralPath $Path)) { throw 'file does not exist after writing' }
            return $true
        } catch {
            Write-Fail ("{0} could not be written: {1} ({2})" -f $Label, $_.Exception.Message, $Path)
            return $false
        }
    }
    if ($Delimiter.Length -ne 1) { throw "'$Delimiter' is not a valid delimiter - it must be exactly one character." }
    if (-not (Test-Path -LiteralPath $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
    $enc = if ($PSVersionTable.PSVersion.Major -ge 6) { 'utf8BOM' } else { 'UTF8' }
    $result = @{ Detail = $null; Software = $null; Overview = $null; Rows = $Zeilen.Count; WriteErrors = 0 }

    $detailDatei = Join-Path $OutputPath ("Inventar_{0}_{1}.csv" -f $Rechnername, $Dateistempel)
    if (Write-InventoryCsv -Data $Zeilen -Path $detailDatei -Label 'Detail CSV') { $result.Detail = $detailDatei; Write-Ok "Detail CSV : $detailDatei ($($Zeilen.Count) rows)" } else { $writeErrors++ }

    if ($Software -ne 'none' -and $SoftwareListe.Count -gt 0) {
        $softwareDatei = Join-Path $OutputPath 'Inventar_Software.csv'
        $swSpalten = @('Zeitstempel','Aufnahmedatum','Hostname','Typ','Name','Version','Hersteller','Installiert_am','Quelle')
        Update-CsvHeader -Path $softwareDatei -Columns $swSpalten -Delimiter $Delimiter -Encoding $enc -Label 'Software CSV'
        $swZeilen = $SoftwareListe | Sort-Object Typ, Name |
            Select-Object @{L='Zeitstempel';E={$Zeitstempel}}, @{L='Aufnahmedatum';E={$Aufnahmedatum}}, @{L='Hostname';E={$Rechnername}},
                          Typ, Name, Version, Hersteller, @{L='Installiert_am';E={$_.Installiert}}, Quelle
        if (Write-InventoryCsv -Data $swZeilen -Path $softwareDatei -Append -Label 'Software CSV') { $result.Software = $softwareDatei; Write-Ok "Software CSV: $softwareDatei (+$($SoftwareListe.Count) rows)" } else { $writeErrors++ }
    }
    if ($Summary) {
        $uebersicht = Join-Path $OutputPath 'Inventar_Uebersicht.csv'
        $spalten = @('Zeitstempel','Aufnahmedatum','Hostname','Kommentar','Hersteller','Modell','Seriennummer','AssetTag','Formfaktor','OS','OSVersion','CPU','CPUKerne',
                     'RAM_GB','RAM_Module','Disks','GPU','MAC_Primaer','IP_Primaer','BIOS_Version','Akku_Gesundheit_Prozent','Monitore','Software_Anzahl','Software_Neueste_Installation')
        Update-CsvHeader -Path $uebersicht -Columns $spalten -Delimiter $Delimiter -Encoding $enc -Label 'Overview CSV'
        $zeile = [ordered]@{ Zeitstempel = $Zeitstempel; Aufnahmedatum = $Aufnahmedatum; Hostname = $Rechnername; Kommentar = $Comment }
        foreach ($k in $spalten) { if (-not $zeile.Contains($k)) { $zeile[$k] = $Kurz[$k] } }
        if (Write-InventoryCsv -Data ([pscustomobject]$zeile) -Path $uebersicht -Append -Label 'Overview CSV') { $result.Overview = $uebersicht; Write-Ok "Overview CSV: $uebersicht (appended)" } else { $writeErrors++ }
    }
    $result.WriteErrors = $writeErrors
    if ($writeErrors -gt 0) { Write-Fail "$writeErrors file(s) could not be written - the inventory is incomplete." }
    if (-not $IstAdmin) { Write-Warn 'Ran without administrator rights - TPM, battery and some disk/RAM details may be missing.' }
    return $result
}

function Invoke-Inventory {
    <# Menu entry: options menu, then the run. #>
    Write-Title 'Inventory'
    while (Show-InventoryMenu) {
        Clear-Host
        Write-Title 'Inventory'
        $null = Invoke-InventoryRun
        Wait-AnyKey 'Press any key to return to the Inventory menu...'
    }
}
