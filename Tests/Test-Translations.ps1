# Run with: pwsh -NoProfile -File Tests/Test-Translations.ps1
# Ensures bundled French and Russian DefInjected entries target current definitions.
$ErrorActionPreference = 'Stop'
$modRoot = Join-Path $PSScriptRoot '..'
$script:checks = 0

function Assert-True($Condition, [string]$Message) {
    $script:checks++
    if (-not $Condition) { throw "FAIL: $Message" }
}

$defs = @{}
Get-ChildItem (Join-Path $modRoot 'Defs') -Recurse -Filter *.xml -File | ForEach-Object {
    $xml = [xml](Get-Content $_.FullName -Raw)
    foreach ($node in $xml.SelectNodes('/Defs/*[defName]')) {
        $defs[$node.defName] = $true
    }
}

$expectedFiles = @(
    'DefInjected/ThingDef/ThingDef.xml',
    'DefInjected/ResearchProjectDef/ResearchProjectDefs.xml',
    'DefInjected/ResearchTabDef/ResearchTabDef.xml'
)
$requiredThingDefs = @('ASNeolithicChunkStorage', 'ASNeolithicLargePotStone', 'ASNeolithicPlinthStone')

foreach ($language in @('French', 'Russian')) {
    $languageRoot = Join-Path $modRoot "Languages/$language"
    Assert-True (Test-Path $languageRoot) "$language language folder exists"
    foreach ($relativePath in $expectedFiles) {
        $path = Join-Path $languageRoot $relativePath
        Assert-True (Test-Path $path) "$language contains $relativePath"
        $xml = [xml](Get-Content $path -Raw)
        foreach ($entry in $xml.LanguageData.ChildNodes | Where-Object NodeType -eq 'Element') {
            $parts = $entry.Name.Split('.', 2)
            $defName = $parts[0]
            Assert-True ($defs.ContainsKey($defName)) "$language translation targets existing def $defName"
            Assert-True (-not [string]::IsNullOrWhiteSpace($entry.InnerText)) "$language translation $($entry.Name) is not empty"
        }
    }

    $thingXml = [xml](Get-Content (Join-Path $languageRoot 'DefInjected/ThingDef/ThingDef.xml') -Raw)
    foreach ($defName in $requiredThingDefs) {
        Assert-True ($null -ne $thingXml.LanguageData.SelectSingleNode("$defName.label")) "$language translates $defName label"
        Assert-True ($null -ne $thingXml.LanguageData.SelectSingleNode("$defName.description")) "$language translates $defName description"
    }
}

$russianPaths = @(git -C $modRoot ls-files 'Languages/Russian/*')
Assert-True (@($russianPaths | Where-Object { $_ -cmatch '/DefInjected/' }).Count -eq 3) 'Russian DefInjected paths use exact case'
Assert-True (@($russianPaths | Where-Object { $_ -cmatch '/Definjected/' }).Count -eq 0) 'Russian DefInjected paths have no incorrectly cased duplicate'

Write-Output "PASS: $script:checks translation assertions"
