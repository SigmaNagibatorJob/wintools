@{
    Severity = @('Error', 'Warning')

    # WinTools is an interactive, colored console UI rather than a reusable
    # PowerShell module. Its menu names are public UX, every mutation has a
    # custom preview/confirmation gate, and the action log is intentionally
    # shared across menus. These design rules are therefore not applicable.
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSUseApprovedVerbs'
        'PSUseSingularNouns'
        'PSAvoidGlobalVars'
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
