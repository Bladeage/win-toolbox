# ---------------------------------------------------------------------------
# tools/adwcleaner.ps1 - download, run and remove Malwarebytes AdwCleaner.
# ---------------------------------------------------------------------------

function Invoke-AdwCleaner {
    <#
    .SYNOPSIS
        Downloads AdwCleaner to %TEMP%, runs it interactively and deletes it afterwards.
    .NOTES
        AdwCleaner asks for elevation itself, so this tool does not need an admin shell.
    #>
    Write-Title 'Malwarebytes AdwCleaner'
    $exe = Join-Path ([IO.Path]::GetTempPath()) 'adwcleaner.exe'
    try {
        Write-Step 'Downloading the latest AdwCleaner...'
        Get-RemoteFile -Uri $Urls.AdwCleaner -OutFile $exe
        Write-Ok "Saved to $exe"

        Write-Step 'Starting AdwCleaner - close it when you are done.'
        Start-Process -FilePath $exe -Wait
        Write-Ok 'AdwCleaner finished.'
    } finally {
        if (Test-Path $exe) {
            Remove-Item $exe -Force -ErrorAction SilentlyContinue
            Write-Ok 'Temporary file removed.'
        }
    }
}
