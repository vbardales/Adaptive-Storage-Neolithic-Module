# Run with: pwsh -NoProfile -File Tests/Test-Mod.ps1
# Static contracts for the stone-as-stuff architecture.
$ErrorActionPreference = 'Stop'
$modRoot = Join-Path $PSScriptRoot '..'
$script:checks = 0

function Assert-True($Condition, [string]$Message) {
    $script:checks++
    if (-not $Condition) { throw "FAIL: $Message" }
}

$xmlFiles = @(Get-ChildItem $modRoot -Recurse -Filter *.xml -File)
$documents = @{}
foreach ($file in $xmlFiles) {
    $xml = New-Object System.Xml.XmlDocument
    $xml.PreserveWhitespace = $true
    $xml.Load($file.FullName)
    $documents[$file.FullName] = $xml
    Assert-True ($null -ne $xml.DocumentElement) "XML document: $($file.FullName)"
}

$defs = New-Object System.Xml.XmlDocument
$defs.LoadXml('<Defs/>')
foreach ($doc in $documents.Values) {
    foreach ($node in $doc.SelectNodes('/Defs/*')) {
        [void]$defs.DocumentElement.AppendChild($defs.ImportNode($node, $true))
    }
}

$identities = @($defs.SelectNodes('/Defs/*[defName]') | ForEach-Object {
    $_.Name + ':' + $_.SelectSingleNode('defName').InnerText
})
Assert-True (@($identities | Group-Object | Where-Object Count -gt 1).Count -eq 0) 'Unique defNames within each Def type'

$meta = [xml](Get-Content (Join-Path $modRoot 'About/About.xml') -Raw)
Assert-True ($meta.ModMetaData.packageId -ceq 'adaptive.storage.neolithic') 'PackageId preserved'
Assert-True ($meta.ModMetaData.name -ceq 'Adaptive Storage Neolithic Module') 'Module name preserved'
Assert-True (@($meta.ModMetaData.supportedVersions.li) -contains '1.6') 'RimWorld 1.6 declared'
Assert-True (@($meta.ModMetaData.modDependencies.li).Count -eq 1) 'Only the framework is a direct dependency'
Assert-True ($meta.ModMetaData.modDependencies.li.packageId -ceq 'adaptive.storage.framework') 'Framework dependency'
Assert-True (@($meta.ModMetaData.loadAfter.li) -contains 'adaptive.storage.framework') 'Framework loadAfter'
Assert-True (Test-Path (Join-Path $modRoot 'About/ModIcon.png')) 'Mod icon present'
Assert-True (Test-Path (Join-Path $modRoot 'About/Preview.png')) 'Preview present'

$thingDefs = @{}
foreach ($node in $defs.SelectNodes('/Defs/ThingDef[defName]')) {
    $thingDefs[$node.defName] = $node
}
foreach ($defName in @('ASNeolithicChunkStorage', 'ASNeolithicLargePotStone', 'ASNeolithicPlinthStone')) {
    Assert-True ($thingDefs.ContainsKey($defName)) "$defName exists"
    Assert-True (@($thingDefs[$defName].stuffCategories.li) -contains 'ASFStoneChunks') "$defName uses ASFStoneChunks"
    Assert-True ([int]$thingDefs[$defName].costStuffCount -gt 0) "$defName consumes stone chunks as stuff"
}
Assert-True ($thingDefs['ASNeolithicChunkStorage'].modExtensions.li.lockStorageSettingsToStuff -ceq 'true') 'Chunk stack locks storage to its stone stuff'

$compatPath = Join-Path $modRoot 'Patches/ChunkBackCompatibility.xml'
Assert-True (Test-Path $compatPath) 'Save compatibility patch present'
$compatText = Get-Content $compatPath -Raw
Assert-True (([regex]::Matches($compatText, 'SaveGameCompatibility.Operation')).Count -eq 3) 'Three building migrations declared'
foreach ($target in @('ASNeolithicChunkStorage', 'ASNeolithicLargePotStone', 'ASNeolithicPlinthStone')) {
    Assert-True ($compatText.Contains("<newDefName>$target</newDefName>")) "Migration targets $target"
}
foreach ($oldPatch in @('ChunkStorage.xml', 'LargePot.xml', 'Plinth.xml')) {
    Assert-True (-not (Test-Path (Join-Path $modRoot "Patches/$oldPatch"))) "Old generated patch removed: $oldPatch"
}

$trackedRussianPaths = @(git -C $modRoot ls-files 'Languages/Russian/*')
Assert-True (@($trackedRussianPaths | Where-Object { $_ -cmatch '/DefInjected/' }).Count -eq 3) 'Russian DefInjected paths use exact case'
Assert-True (@($trackedRussianPaths | Where-Object { $_ -cmatch '/Definjected/' }).Count -eq 0) 'No wrongly cased Russian path'

$textureRoot = Join-Path $modRoot 'Textures'
$textureFiles = @(Get-ChildItem $textureRoot -Recurse -File)
$textureKeys = @{}
foreach ($file in $textureFiles) {
    $relative = [IO.Path]::GetRelativePath($textureRoot, $file.FullName).Replace('\', '/')
    $textureKeys[$relative] = $true
}
foreach ($doc in $documents.Values) {
    foreach ($node in $doc.SelectNodes('//texPath | //uiIconPath')) {
        $path = $node.InnerText.Trim()
        if (-not $path) { continue }
        $direct = $textureKeys.ContainsKey("$path.png") -or $textureKeys.ContainsKey("$path.dds")
        $directional = @($textureKeys.Keys | Where-Object { $_ -clike "$path`_*.png" -or $_ -clike "$path`_*.dds" }).Count -gt 0
        Assert-True ($direct -or $directional) "Texture path resolves with exact case: $path"
    }
}

$research = $defs.SelectNodes('/Defs/ResearchProjectDef[defName]')
Assert-True ($research.Count -eq 2) 'Two concrete research projects'
Assert-True (@($research | Where-Object { $_.tags.li -contains 'TribalStart' }).Count -eq 1) 'Neolithic storage remains available to tribal starts'

$biotechGraphics = $defs.SelectNodes('/Defs/AdaptiveStorage.GraphicsDef[@MayRequire="Ludeon.RimWorld.Biotech"]')
Assert-True ($biotechGraphics.Count -eq 2) 'Biotech toxipotato graphics remain optional'

Write-Output "PASS: $script:checks assertions across $($xmlFiles.Count) XML files and $($textureFiles.Count) texture files"
