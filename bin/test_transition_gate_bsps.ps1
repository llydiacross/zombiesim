param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$BuildDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'skybox_models.psm1') -Force
$maps = 0
$gates = 0
$landmarks = 0
foreach ($file in Get-ChildItem -LiteralPath $SourceDirectory -Filter '*.vmf' -File) {
    $source = [ZombieSim.Skybox.KeyValuesParser]::Parse((Get-Content -LiteralPath $file.FullName -Raw))
    $expected = @($source.Children | Where-Object {
        $_.Get('classname') -eq 'trigger_multiple' -and $_.Get('targetname') -match '^zm_transition_gate_[NESW]$'
    })
    if ($expected.Count -eq 0) { continue }
    $bsp = Join-Path $BuildDirectory ([IO.Path]::ChangeExtension($file.Name, '.bsp'))
    $bytes = [IO.File]::ReadAllBytes($bsp)
    if ($bytes.Length -lt 24 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'VBSP') {
        throw "Invalid gate fixture BSP: $bsp"
    }
    $offset = [BitConverter]::ToInt32($bytes, 8)
    $length = [BitConverter]::ToInt32($bytes, 12)
    if ($offset -lt 0 -or $length -lt 1 -or [long]$offset + $length -gt $bytes.Length) {
        throw "Invalid BSP entity lump: $bsp"
    }
    $entities = [ZombieSim.Skybox.KeyValuesParser]::Parse(
        [Text.Encoding]::ASCII.GetString($bytes, $offset, $length).TrimEnd([char]0)
    ).Children
    foreach ($gate in @($expected | Where-Object { $_.Get('classname') -eq 'trigger_multiple' })) {
        $direction = $gate.Get('zm_transition_direction').ToUpperInvariant()
        $arrivalName = "${direction}_ENTRANCE"
        $arrival = @($source.Children | Where-Object { $_.Get('classname') -eq 'info_landmark' -and $_.Get('targetname') -eq $arrivalName })
        if ($arrival.Count -ne 1) { throw "Missing/duplicated source arrival $arrivalName in $($file.Name)" }
        $expected += $arrival
        $gates++
    }
    foreach ($entity in $expected) {
        $name = $entity.Get('targetname')
        $matches = @($entities | Where-Object { $_.Get('targetname') -eq $name })
        if ($matches.Count -ne 1) { throw "Missing/duplicated compiled gate entity $name in $bsp" }
        foreach ($key in 'classname', 'origin', 'angles', 'model') {
            if ($key -eq 'model' -and $entity.Get('classname') -eq 'trigger_multiple') { continue }
            $value = $entity.Get($key)
            if (-not [string]::IsNullOrWhiteSpace($value) -and $matches[0].Get($key) -ne $value) {
                throw "Compiled gate entity $name changed $key in $bsp"
            }
        }
        if ($entity.Get('classname') -eq 'trigger_multiple' -and $matches[0].Get('model') -notmatch '^\*\d+$') {
            throw "Compiled gate $name has no brush model in $bsp"
        }
        if ($entity.Get('classname') -eq 'info_landmark') { $landmarks++ }
    }
    $maps++
}
if ($maps -eq 0 -or $gates -eq 0 -or $landmarks -ne $gates) {
    throw "Incomplete compiled gate coverage: $maps maps, $gates gates, $landmarks arrivals"
}
Write-Output "Compiled gate checks: $maps maps, $gates gates and $landmarks arrivals retain source placement."
