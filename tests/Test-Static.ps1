[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptFiles = @(
    (Join-Path $repoRoot "install.ps1"),
    (Join-Path $repoRoot "wintools_ru.ps1"),
    (Join-Path $repoRoot "wintools_en.ps1")
)
$failures = New-Object System.Collections.Generic.List[string]

function Assert-True($condition, $message) {
    if (-not $condition) { $script:failures.Add($message) }
}

$asts = @{}
foreach ($file in $scriptFiles) {
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $file,
        [ref]$tokens,
        [ref]$parseErrors
    )
    $asts[[IO.Path]::GetFileName($file)] = $ast
    Assert-True ($parseErrors.Count -eq 0) "$file has $($parseErrors.Count) parser error(s)"
    $bytes = [IO.File]::ReadAllBytes($file)
    $hasUtf8Bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    Assert-True $hasUtf8Bom "$file must use UTF-8 BOM for Windows PowerShell 5.1"
}

$requiredMenus = @(
    "Menu-Services", "Menu-Registry", "Menu-Tasks", "Menu-Startup",
    "Menu-DiskCleanup", "Menu-Monitor", "Menu-PowerPlan", "Menu-SMB",
    "Menu-Health", "Menu-DriverUpdate", "Menu-RestorePoint", "Menu-ChangeLog",
    "Menu-Bloatware", "Menu-BrowserCache", "Menu-Cosmetics", "Menu-Profiles",
    "Menu-Snapshots", "Menu-Diagnostics", "Menu-Applications", "Menu-Update",
    "Main-Menu"
)

$requiredReleaseFunctions = @(
    "Get-WinToolsRegistryTargets", "Get-WinToolsStartupPaths",
    "Export-WinToolsSnapshot", "Import-WinToolsSnapshot",
    "Get-WinToolsUpdateManifest", "Invoke-WinToolsUpdate", "Test-WinToolsUpdate"
)

$languageFunctions = @{}
foreach ($name in @("wintools_ru.ps1", "wintools_en.ps1")) {
    $ast = $asts[$name]
    $source = Get-Content (Join-Path $repoRoot $name) -Raw
    $functions = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true) | ForEach-Object { $_.Name })
    $languageFunctions[$name] = $functions

    foreach ($menu in $requiredMenus) {
        Assert-True ($functions -contains $menu) "$name is missing function $menu"
    }
    foreach ($functionName in $requiredReleaseFunctions) {
        Assert-True ($functions -contains $functionName) "$name is missing function $functionName"
    }

    Assert-True ($source -match '\$Script:WinToolsVersion\s*=\s*"2\.0\.0"') "$name does not declare WinTools 2.0.0"
    foreach ($number in 16..20) {
        Assert-True ($source -match ('"{0}"\s*\{{\s*Menu-' -f $number)) "$name does not wire main-menu item $number"
    }
    Assert-True ($source -match 'Test-WinToolsUpdate\s+-startupCheck') "$name has no startup update check"
    Assert-True ($source -match 'Get-FileHash[\s\S]*SHA256') "$name updater does not verify SHA-256"
    Assert-True ($source -match 'mutationStarted[\s\S]*rolled back|mutationStarted[\s\S]*отменено') "$name updater does not describe rollback"

    $parameters = @($ast.ParamBlock.Parameters | ForEach-Object {
        $_.Name.VariablePath.UserPath
    })
    Assert-True ($parameters -contains "WindowsVersion") "$name does not accept -WindowsVersion"
    Assert-True ($source -match 'win11enterprise') "$name does not distinguish Enterprise from Enterprise LTSC"
    Assert-True ($source -notmatch '\bGet-WmiObject\b') "$name is not compatible with PowerShell 7"
    $badSetItemProperty = @($ast.FindAll({
        param($node)
        if ($node -isnot [System.Management.Automation.Language.CommandAst]) { return $false }
        if ($node.GetCommandName() -ne "Set-ItemProperty") { return $false }
        return @($node.CommandElements | ForEach-Object { $_.Extent.Text }) -contains "-Type"
    }, $true))
    Assert-True ($badSetItemProperty.Count -eq 0) "$name still uses invalid Set-ItemProperty -Type"
    Assert-True ($source -match 'New-ItemProperty[^\r\n]*-PropertyType\s+\$type') "$name registry helper does not preserve value type"
    Assert-True ($source -match 'finally\s*\{[\s\S]*Start-Service\s+-Name\s+wuauserv') "$name does not restore Windows Update after cleanup"
    Assert-True ($source -match 'Get-BrowserCachePaths') "$name does not scan browser profiles"
    Assert-True ($source -match 'function\s+Get-TweakEnabled') "$name does not report tweak state"
    Assert-True ($source -match 'function\s+Set-TweakState') "$name does not support enabling/disabling tweaks"
    Assert-True ($source -match 'function\s+ConvertTo-TweakActions') "$name does not parse tweak lists and ranges"
    Assert-True ($source -match '\$inputText\s+-split\s+","') "$name does not accept comma-separated tweak commands"
}

$ruMenus = @($languageFunctions["wintools_ru.ps1"] | Where-Object { $_ -like "Menu-*" } | Sort-Object -Unique)
$enMenus = @($languageFunctions["wintools_en.ps1"] | Where-Object { $_ -like "Menu-*" } | Sort-Object -Unique)
Assert-True ((Compare-Object $ruMenus $enMenus).Count -eq 0) "RU and EN menu function sets differ"

$installerCommands = @($asts["install.ps1"].FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.CommandAst]
}, $true) | ForEach-Object { $_.GetCommandName() })
Assert-True ($installerCommands -notcontains "Invoke-Expression") "install.ps1 still executes downloaded text through Invoke-Expression"
Assert-True ($installerCommands -contains "Invoke-RestMethod") "install.ps1 no longer downloads the selected script"

if ($failures.Count -gt 0) {
    Write-Host "Static checks failed:" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host "Static checks passed for install.ps1 and both WinTools languages." -ForegroundColor Green
