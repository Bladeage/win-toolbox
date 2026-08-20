@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',                         # interactive console tool - Write-Host is the point
        'PSAvoidUsingInvokeExpression',                  # irm | iex wrappers are the whole purpose
        'PSUseShouldProcessForStateChangingFunctions',   # Install-*/Invoke-* here are interactive, no -WhatIf story
        'PSUseSingularNouns'                             # Install-GamingRedists, Install-WinGetPackage ...
    )
    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }
    }
}
