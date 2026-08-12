[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    "PSAvoidOverwritingBuiltInCmdlets",
    "",
    Justification = "This isolated test intentionally mocks console input/output."
)]
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

foreach ($scriptFile in @("wintools_ru.ps1", "wintools_en.ps1")) {
    $path = Join-Path $repoRoot $scriptFile
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw "$scriptFile has parser errors" }

    foreach ($functionName in @("ConvertTo-NumberList", "Confirm-ActionPreview")) {
        $functionAst = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $functionName
        }, $true) | Select-Object -First 1
        if (-not $functionAst) { throw "$scriptFile has no $functionName" }
        . ([scriptblock]::Create($functionAst.Extent.Text))
    }

    $numbers = @(ConvertTo-NumberList "1,3,5-7,3" 10)
    $actual = $numbers -join ","
    if ($actual -ne "1,3,5,6,7") { throw "$scriptFile parsed number lists incorrectly: $actual" }

    $rangeFailed = $false
    try { $null = ConvertTo-NumberList "8-12" 10 } catch { $rangeFailed = $true }
    if (-not $rangeFailed) { throw "$scriptFile accepted an out-of-range selection" }

    $script:answer = ""
    function Write-Host { param([Parameter(ValueFromRemainingArguments)]$Arguments) $null = $Arguments }
    function Read-Host { return $script:answer }

    if (Confirm-ActionPreview @("test")) { throw "$scriptFile applies changes after an empty Enter" }
    $script:answer = "N"
    if (Confirm-ActionPreview @("test")) { throw "$scriptFile applies changes after N" }
    $script:answer = "Y"
    if (-not (Confirm-ActionPreview @("test"))) { throw "$scriptFile rejects Y confirmation" }

    $source = Get-Content $path -Raw
    if ($source -notmatch 'Enable-Svc' -or $source -notmatch 'Disable-Svc') {
        throw "$scriptFile services are not bidirectional"
    }
    if ($source -notmatch 'Enable-ScheduledTask' -or $source -notmatch 'Disable-ScheduledTask') {
        throw "$scriptFile scheduled tasks are not bidirectional"
    }
    if ($source -notmatch 'WinToolsDisabled' -or $source -notmatch 'StartupToggle') {
        throw "$scriptFile startup entries are not safely toggled"
    }

    Remove-Item Function:\ConvertTo-NumberList, Function:\Confirm-ActionPreview,
        Function:\Write-Host, Function:\Read-Host -Force
    Microsoft.PowerShell.Utility\Write-Host "Stage 1 control checks passed: $scriptFile" -ForegroundColor Green
}
