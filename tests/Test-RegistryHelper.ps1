[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    "PSAvoidOverwritingBuiltInCmdlets",
    "",
    Justification = "This isolated test intentionally mocks registry provider cmdlets."
)]
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptFiles = @("wintools_ru.ps1", "wintools_en.ps1")

foreach ($scriptFile in $scriptFiles) {
    $path = Join-Path $repoRoot $scriptFile
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $path,
        [ref]$tokens,
        [ref]$errors
    )
    if ($errors.Count) { throw "$scriptFile has parser errors" }

    $helper = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq "Set-RegLogged"
    }, $true) | Select-Object -First 1
    if (-not $helper) { throw "$scriptFile has no Set-RegLogged helper" }

    # Load only the helper. The Windows-only script body is intentionally not run.
    . ([scriptblock]::Create($helper.Extent.Text))

    $script:mockKeys = @{}
    $script:mockValues = @{}
    $script:mockTypes = @{}
    $script:mockLog = @()

    function Test-Path([string]$Path) {
        return $script:mockKeys.ContainsKey($Path)
    }
    function New-Item([string]$Path, [switch]$Force, $ErrorAction) {
        $script:mockKeys[$Path] = $true
    }
    function Get-ItemPropertyValue([string]$Path, [string]$Name, $ErrorAction) {
        $key = "$Path|$Name"
        if (-not $script:mockValues.ContainsKey($key)) { throw "missing value" }
        return $script:mockValues[$key]
    }
    function New-ItemProperty([string]$Path, [string]$Name, $Value, $PropertyType, [switch]$Force, $ErrorAction) {
        if ($Name -eq "FailWrite") { throw "simulated write failure" }
        $script:mockKeys[$Path] = $true
        $key = "$Path|$Name"
        $script:mockValues[$key] = $Value
        $script:mockTypes[$key] = "$PropertyType"
    }
    function Write-ActionLog($type, $target, $oldValue, $desc) {
        $script:mockLog += [pscustomobject]@{
            Type = $type; Target = $target; OldValue = $oldValue; Desc = $desc
        }
    }

    Set-RegLogged "Mock:\New" "Enabled" 1 "DWord" "new value"
    if ($script:mockValues["Mock:\New|Enabled"] -ne 1) { throw "$scriptFile did not write a new value" }
    if ($script:mockTypes["Mock:\New|Enabled"] -ne "DWord") { throw "$scriptFile lost the registry value type" }
    if ($script:mockLog.Count -ne 1 -or $null -ne $script:mockLog[0].OldValue) { throw "$scriptFile logged an incorrect missing value" }

    $script:mockValues["Mock:\Existing|Enabled"] = 7
    $script:mockKeys["Mock:\Existing"] = $true
    Set-RegLogged "Mock:\Existing" "Enabled" 2 "DWord" "existing value"
    if ($script:mockValues["Mock:\Existing|Enabled"] -ne 2) { throw "$scriptFile did not update an existing value" }
    if ($script:mockLog.Count -ne 2 -or $script:mockLog[1].OldValue -ne 7) { throw "$scriptFile did not preserve the old value" }

    $beforeFailureLogCount = $script:mockLog.Count
    $failedAsExpected = $false
    try {
        Set-RegLogged "Mock:\Failure" "FailWrite" 1 "DWord" "failure"
    } catch {
        $failedAsExpected = $true
    }
    if (-not $failedAsExpected) { throw "$scriptFile hid a registry write failure" }
    if ($script:mockLog.Count -ne $beforeFailureLogCount) { throw "$scriptFile logged a failed write as successful" }

    Remove-Item Function:\Test-Path, Function:\New-Item, Function:\Get-ItemPropertyValue,
        Function:\New-ItemProperty, Function:\Write-ActionLog, Function:\Set-RegLogged -Force

    Write-Host "Registry helper checks passed: $scriptFile" -ForegroundColor Green
}
