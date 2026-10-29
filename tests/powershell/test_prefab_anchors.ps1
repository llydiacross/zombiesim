param([string]$OutputDirectory = '', [string]$BspPath = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$bin = Join-Path $root 'bin'
$profile = & (Join-Path $bin 'resolve_world_generation_profile.ps1') -WorldProfile preview
Import-Module (Join-Path $bin 'skybox_models.psm1') -Force
$temporary = [string]::IsNullOrWhiteSpace($OutputDirectory)
if ($temporary) { $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) ('zm-prefab-anchor-' + [guid]::NewGuid().ToString('N')) }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$null = [IO.Directory]::CreateDirectory($OutputDirectory)
$passed = 0
function Assert-Anchor([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:passed++
}
function Write-AnchorSource([string]$Path, [string]$Text) {
    if (-not (Test-Path -LiteralPath $Path) -or [IO.File]::ReadAllText($Path) -cne $Text) {
        [IO.File]::WriteAllText($Path, $Text)
    }
}
function Read-Ast([string]$Name) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $bin $Name), [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw "$Name has PowerShell parse errors: $errors" }
    return $ast
}
try {
    $builder = Read-Ast 'build_cell_vmfs.ps1'
    $zoo = Read-Ast 'build_sign_zoo.ps1'
    foreach ($pair in @(@($builder, 'Get-TransformedInstancePointEntities'), @($zoo, 'New-ZooBox'), @($zoo, 'New-ZooEntity'))) {
        $name = $pair[1]
        $definition = @($pair[0].FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
        }, $true))
        Assert-Anchor ($definition.Count -eq 1) "Missing helper $name."
        . ([scriptblock]::Create($definition[0].Extent.Text))
    }
    $assignment = @($builder.FindAll({
        param($node)
        $node -is [Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left.Extent.Text -eq '$instanceTransformedClasses'
    }, $true))
    Assert-Anchor ($assignment.Count -eq 1) 'Missing instance class registry.'
    . ([scriptblock]::Create($assignment[0].Extent.Text))
    Assert-Anchor ($instanceTransformedClasses -contains 'zn_prefab_anchor') 'Prefab anchors are not transformed.'
    $script:nextId = 100
    $localAnchor = New-ZooEntity ([ordered]@{
        classname = 'zn_prefab_anchor'; origin = '32 16 64'; angles = '0 90 0'
        prefab_tags = 'road, motorway'; instance_local = '1'
    })
    $source = Join-Path $OutputDirectory 'anchor-source.vmf'
    Write-AnchorSource $source "world`r`n{`r`n `"id`" `"1`"`r`n `"classname`" `"worldspawn`"`r`n}`r`n$localAnchor"
    $expected = @()
    $entities = [Collections.Generic.List[string]]::new()
    foreach ($yaw in @(0, 90, 180, 270)) {
        $originX = $yaw * 2 - 270
        $transformed = Get-TransformedInstancePointEntities $source $originX 0 0 $yaw $script:nextId
        $script:nextId = $transformed.NextEntityId
        $text = $transformed.Lines -join "`r`n"
        $node = [ZombieSim.Skybox.KeyValuesParser]::Parse($text).Children[0]
        $radians = $yaw * [Math]::PI / 180
        $x = $originX + [Math]::Round(32 * [Math]::Cos($radians) - 16 * [Math]::Sin($radians))
        $y = [Math]::Round(32 * [Math]::Sin($radians) + 16 * [Math]::Cos($radians))
        Assert-Anchor ($node.Get('origin') -eq "$x $y 64") "Incorrect origin for yaw $yaw."
        Assert-Anchor ($node.Get('angles') -eq "0 $(($yaw + 90) % 360) 0") "Incorrect angle for yaw $yaw."
        Assert-Anchor ($node.Get('prefab_tags') -eq 'road, motorway' -and $node.Get('zm_instance_transformed') -eq '1') 'Anchor metadata lost.'
        $expected += @{ origin = $node.Get('origin'); angles = $node.Get('angles') }
        $entities.Add($text)
        $entities.Add((New-ZooEntity ([ordered]@{
            classname = 'func_instance'; file = ('../' + [IO.Path]::GetFileName($OutputDirectory) + '/anchor-source.vmf')
            origin = "$originX 0 0"; angles = "0 $yaw 0"; fixup_style = '2'
        })))
    }
    $control = $localAnchor.Replace('zn_prefab_anchor', 'zn_safezone_arrival')
    $controlPath = Join-Path $OutputDirectory 'control.vmf'
    [IO.File]::WriteAllText($controlPath, $control)
    $result = Get-TransformedInstancePointEntities $controlPath 100 200 10 90 1000
    $node = [ZombieSim.Skybox.KeyValuesParser]::Parse(($result.Lines -join "`r`n")).Children[0]
    Assert-Anchor ($node.Get('origin') -eq '84 232 74' -and $node.Get('angles') -eq '0 180 0') 'Safe-zone transform behavior changed.'
    [IO.File]::WriteAllText($controlPath, $localAnchor.Replace('"instance_local" "1"', '"instance_local" "0"'))
    $rejected = $false
    try { Get-TransformedInstancePointEntities $controlPath 0 0 0 0 1000 | Out-Null } catch { $rejected = $true }
    Assert-Anchor $rejected 'Unmarked instance-local anchor was not rejected.'
    Remove-Item -LiteralPath $controlPath
    $brushes = @(
        (New-ZooBox -1024 -640 -32 1024 640 0),
        (New-ZooBox -1024 -640 512 1024 640 544),
        (New-ZooBox -1056 -640 -32 -1024 640 544),
        (New-ZooBox 1024 -640 -32 1056 640 544),
        (New-ZooBox -1056 -640 -32 1056 -608 544),
        (New-ZooBox -1056 608 -32 1056 640 544)
    )
    $entities.Add((New-ZooEntity ([ordered]@{ classname = 'info_player_start'; origin = '0 -256 16'; angles = '0 90 0' })))
    $entities.Add((New-ZooEntity ([ordered]@{ classname = 'light'; origin = '0 0 400'; _light = '255 255 255 400' })))
    $entities.Add((New-ZooEntity ([ordered]@{ classname = 'zn_world_profile'; world_profile = 'preview'; origin = '0 0 16' })))
    $entities.Add((New-ZooEntity ([ordered]@{ classname = 'zn_prefab_anchor'; prefab_tags = 'road'; origin = '0 256 64'; angles = '0 45 0' })))
    $vmf = "world`r`n{`r`n `"id`" `"1`"`r`n `"classname`" `"worldspawn`"`r`n `"skyname`" `"sky_day01_01`"`r`n$($brushes -join "`r`n")`r`n}`r`n$($entities -join "`r`n")"
    Write-AnchorSource (Join-Path $OutputDirectory 'zn_dev_prefab_anchor.vmf') $vmf
    Write-AnchorSource (Join-Path $OutputDirectory 'required.txt') "zn_dev_prefab_anchor.vmf`r`n"
    Write-AnchorSource (Join-Path $OutputDirectory 'plan.json') '{"schemaVersion":2,"safeZoneMaps":[]}'
    if ($BspPath) {
        $bytes = [IO.File]::ReadAllBytes($BspPath)
        Assert-Anchor ([Text.Encoding]::ASCII.GetString($bytes, 0, 4) -eq 'VBSP') 'Invalid BSP.'
        $offset = [BitConverter]::ToInt32($bytes, 8)
        $length = [BitConverter]::ToInt32($bytes, 12)
        $parsed = [ZombieSim.Skybox.KeyValuesParser]::Parse([Text.Encoding]::ASCII.GetString($bytes, $offset, $length).TrimEnd([char]0))
        $anchors = @($parsed.Children | Where-Object { $_.Get('classname') -eq 'zn_prefab_anchor' })
        $worldAnchors = @($anchors | Where-Object { $_.Get('zm_instance_transformed') -eq '1' })
        Assert-Anchor ($worldAnchors.Count -eq 4) 'Compiled fixture must contain four transformed anchors.'
        foreach ($record in $expected) {
            $match = @($worldAnchors | Where-Object { $_.Get('origin') -eq $record.origin -and $_.Get('angles') -eq $record.angles })
            Assert-Anchor ($match.Count -eq 1) "Compiled anchor transform mismatch: $($record.origin)."
        }
        Assert-Anchor (@($anchors | Where-Object { $_.Get('origin') -eq '0 256 64' -and $_.Get('instance_local') -ne '1' }).Count -eq 1) 'Direct anchor was not retained.'
        Assert-Anchor (@($anchors | Where-Object { $_.Get('instance_local') -eq '1' -and $_.Get('zm_instance_transformed') -ne '1' }).Count -eq 4) 'Raw instance copies lost their skip flag.'
    }
    Write-Output "Prefab anchor fixtures: $passed assertions passed."
} finally {
    if ($temporary -and (Test-Path -LiteralPath $OutputDirectory)) { Remove-Item -LiteralPath $OutputDirectory -Recurse -Force }
}
