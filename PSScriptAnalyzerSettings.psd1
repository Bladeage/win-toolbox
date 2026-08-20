@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',                         # interactive console tool - Write-Host is the point
        'PSAvoidUsingInvokeExpression',                  # irm | iex wrappers are the whole purpose
        'PSUseShouldProcessForStateChangingFunctions',   # Install-*/Invoke-* here are interactive, no -WhatIf story
        'PSUseSingularNouns',                            # Install-WinGetPackage, Update-WinGetSources ...
        'PSUseDeclaredVarsMoreThanAssignments',          # src/*.ps1 are concatenated: $Urls & co. are used across files
        'PSReviewUnusedParameter'                        # false positives: params used inside -Action/-Present scriptblock closures
    )
    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }
    }
}
