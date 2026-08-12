[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    "PSAvoidOverwritingBuiltInCmdlets",
    "",
    Justification = "This isolated test mocks web download and hashing commands."
)]
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = New-Object System.Collections.Generic.List[string]

function Assert-True($condition, $message) {
    if (-not $condition) { $script:failures.Add($message) }
}

foreach ($scriptFile in @("wintools_ru.ps1", "wintools_en.ps1")) {
    $path = Join-Path $repoRoot $scriptFile
    $source = Get-Content $path -Raw
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    Assert-True ($parseErrors.Count -eq 0) "$scriptFile has parser errors"

    foreach ($profilePattern in @(
        "Gaming Desktop|Игровой ПК", "Gaming Laptop|Игровой ноутбук",
        "Balanced|Сбалансированный", "Privacy|Приватность",
        "Windows Defaults|Стандарт Windows"
    )) {
        Assert-True ($source -match $profilePattern) "$scriptFile is missing profile $profilePattern"
    }
    Assert-True ($source -match 'before_profile_') "$scriptFile does not snapshot before profiles"
    Assert-True ($source -match 'before_import') "$scriptFile does not snapshot before imports"
    Assert-True ($source -match 'FormatVersion\s*=\s*1') "$scriptFile does not version snapshot JSON"
    foreach ($field in @("Registry", "Services", "Tasks", "Startup", "ActivePowerScheme")) {
        Assert-True ($source -match ("{0}=" -f $field)) "$scriptFile snapshot is missing $field"
    }
    Assert-True ($source -match 'Get-WinEvent[\s\S]*diagnostic_') "$scriptFile diagnostics are incomplete"
    foreach ($pack in @("Games|Игры", "Internet|Интернет", "Security|Безопасность", "Basic|Базовый")) {
        Assert-True ($source -match $pack) "$scriptFile is missing application pack $pack"
    }
    foreach ($id in @("Valve.Steam", "Mozilla.Firefox", "Bitwarden.Bitwarden", "7zip.7zip")) {
        Assert-True ($source -match [regex]::Escape($id)) "$scriptFile is missing winget package $id"
    }
    Assert-True ($source -match 'Confirm-ActionPreview[^\r\n]*selected') "$scriptFile application installs have no preview"
    Assert-True ($source -match 'Get-FileHash[^\r\n]*SHA256') "$scriptFile updater does not hash downloads"
    Assert-True ($source -match 'Backups') "$scriptFile updater does not create backups"
    Assert-True ($source -match 'mutationStarted') "$scriptFile updater does not guard rollback"
    Assert-True ($source -match '\[L/N/Enter\]') "$scriptFile updater does not offer Later"

    $updateAst = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq "Invoke-WinToolsUpdate"
    }, $true) | Select-Object -First 1
    if (-not $updateAst) { $failures.Add("$scriptFile has no Invoke-WinToolsUpdate"); continue }
    . ([scriptblock]::Create($updateAst.Extent.Text))

    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ("wintools-update-test-" + [guid]::NewGuid())
    $installRoot = Join-Path $testRoot "install"
    $script:payloadRoot = Join-Path $testRoot "payload"
    $env:ProgramData = Join-Path $testRoot "programdata"
    New-Item $installRoot, $script:payloadRoot -ItemType Directory -Force | Out-Null

    function Write-OK($message) { $null = $message }
    function Write-INFO($message) { $null = $message }
    function Write-FAIL($message) { $null = $message }
    function Invoke-WebRequest {
        [CmdletBinding()]
        param([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing, [int]$TimeoutSec)
        $null = $UseBasicParsing, $TimeoutSec
        $name = $Uri.Substring($Uri.LastIndexOf('/') + 1)
        Copy-Item (Join-Path $script:payloadRoot $name) $OutFile -Force
    }

    try {
        Set-Content (Join-Path $installRoot "a.txt") "old-a" -NoNewline
        Set-Content (Join-Path $installRoot "b.txt") "old-b" -NoNewline
        Set-Content (Join-Path $script:payloadRoot "a.txt") "new-a" -NoNewline
        Set-Content (Join-Path $script:payloadRoot "b.txt") "new-b" -NoNewline
        $manifest = [pscustomobject]@{
            version = "9.9.9"
            files = @(
                [pscustomobject]@{path="a.txt"; sha256=(Microsoft.PowerShell.Utility\Get-FileHash (Join-Path $script:payloadRoot "a.txt") -Algorithm SHA256).Hash},
                [pscustomobject]@{path="b.txt"; sha256=(Microsoft.PowerShell.Utility\Get-FileHash (Join-Path $script:payloadRoot "b.txt") -Algorithm SHA256).Hash}
            )
        }
        $updated = Invoke-WinToolsUpdate $manifest -installRoot $installRoot -downloadBase "https://example.invalid"
        Assert-True $updated "$scriptFile updater rejected valid staged files"
        Assert-True ((Get-Content (Join-Path $installRoot "a.txt") -Raw) -eq "new-a") "$scriptFile updater did not install a valid file"

        # A bad hash must fail before any installed file is modified.
        Set-Content (Join-Path $installRoot "a.txt") "stable" -NoNewline
        $badManifest = [pscustomobject]@{
            version = "9.9.9"
            files = @([pscustomobject]@{path="a.txt"; sha256=("0" * 64)})
        }
        $updated = Invoke-WinToolsUpdate $badManifest -installRoot $installRoot -downloadBase "https://example.invalid"
        Assert-True (-not $updated) "$scriptFile updater accepted an invalid hash"
        Assert-True ((Get-Content (Join-Path $installRoot "a.txt") -Raw) -eq "stable") "$scriptFile updater mutated files before hash validation"

        # Simulate a post-copy verification failure on the second file. Both
        # destinations must return to their pre-update contents.
        Set-Content (Join-Path $installRoot "a.txt") "rollback-a" -NoNewline
        Set-Content (Join-Path $installRoot "b.txt") "rollback-b" -NoNewline
        $script:failHashPath = [IO.Path]::GetFullPath((Join-Path $installRoot "b.txt"))
        function Get-FileHash {
            [CmdletBinding()]
            param([Parameter(Mandatory)][string]$Path, [string]$Algorithm)
            if ([IO.Path]::GetFullPath($Path) -eq $script:failHashPath) { throw "simulated verification failure" }
            Microsoft.PowerShell.Utility\Get-FileHash -Path $Path -Algorithm $Algorithm
        }
        $updated = Invoke-WinToolsUpdate $manifest -installRoot $installRoot -downloadBase "https://example.invalid"
        Assert-True (-not $updated) "$scriptFile updater ignored a post-copy failure"
        Assert-True ((Get-Content (Join-Path $installRoot "a.txt") -Raw) -eq "rollback-a") "$scriptFile updater did not roll back the first file"
        Assert-True ((Get-Content (Join-Path $installRoot "b.txt") -Raw) -eq "rollback-b") "$scriptFile updater did not roll back the second file"
    } finally {
        Remove-Item Function:\Get-FileHash -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-WinToolsUpdate, Function:\Invoke-WebRequest,
            Function:\Write-OK, Function:\Write-INFO, Function:\Write-FAIL -Force -ErrorAction SilentlyContinue
        Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:ProgramData\WinTools" -Recurse -Force -ErrorAction SilentlyContinue
    }

    Microsoft.PowerShell.Utility\Write-Host "Release feature checks passed: $scriptFile" -ForegroundColor Green
}

$manifestPath = Join-Path $repoRoot "version.json"
Assert-True (Test-Path $manifestPath) "version.json is missing"
if (Test-Path $manifestPath) {
    try {
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        Assert-True ($manifest.version -eq "2.0.0") "version.json does not declare 2.0.0"
        foreach ($file in @($manifest.files)) {
            $target = Join-Path $repoRoot $file.path
            Assert-True (Test-Path $target) "version.json references missing file $($file.path)"
            if (Test-Path $target) {
                $actual = (Microsoft.PowerShell.Utility\Get-FileHash $target -Algorithm SHA256).Hash
                Assert-True ($actual -eq $file.sha256) "version.json hash mismatch for $($file.path)"
            }
        }
    } catch {
        $failures.Add("Could not validate version.json: $($_.Exception.Message)")
    }
}

if ($failures.Count -gt 0) {
    Write-Host "Release feature checks failed:" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}
Write-Host "All release 2.0 feature checks passed." -ForegroundColor Green
