Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-WorkshopPath {
    param([string]$Path)
    $value = $Path.Replace('\', '/')
    if ($value -notmatch '^[a-zA-Z0-9_ ./-]+$' -or $value.StartsWith('/') -or
        @($value.Split('/') | Where-Object { $_ -in '', '.', '..' }).Count -gt 0) {
        throw "Unsafe Workshop virtual path: $Path"
    }
    return $value.ToLowerInvariant()
}

function Get-WorkshopTextHash {
    param([string]$Text)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant()
    } finally { $algorithm.Dispose() }
}

function Resolve-WorkshopId {
    param([string]$Value, [string]$PackageId)
    if ($Value -eq '' -or $Value -eq "pending:$PackageId") {
        return [pscustomobject]@{ id = ''; placeholder = "pending:$PackageId" }
    }
    if ($Value -notmatch '^[1-9]\d*$') { throw "Invalid Workshop ID for ${PackageId}: $Value" }
    return [pscustomobject]@{ id = $Value; placeholder = '' }
}

function Add-WorkshopFile {
    param([hashtable]$Inventory, [string]$Source, [string]$Path, [string]$Family,
        [string]$Group, [AllowNull()][string]$Text = $null)
    $pathKey = ConvertTo-WorkshopPath $Path
    if ($Inventory.ContainsKey($pathKey)) { throw "Duplicate Workshop virtual path: $pathKey" }
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "Missing package dependency: $Source" }
    $item = Get-Item -LiteralPath $Source
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Package source is a reparse point: $Source" }
    $bytes = $item.Length
    $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash.ToLowerInvariant()
    $hash = $sourceHash
    $transformed = $PSBoundParameters.ContainsKey('Text')
    if ($transformed) {
        $bytes = [Text.Encoding]::UTF8.GetByteCount($Text)
        $hash = Get-WorkshopTextHash $Text
    }
    $Inventory[$pathKey] = [pscustomobject]@{
        path = $pathKey; source = $item.FullName; family = $Family; group = $Group
        bytes = [long]$bytes; sha256 = $hash; text = $(if ($transformed) { $Text } else { $null })
        sourceHash = $sourceHash
    }
}

function Split-WorkshopPackages {
    param([object[]]$Files, [long]$CapacityBytes)
    if ($CapacityBytes -le 0) { throw 'Workshop shard capacity must be positive.' }
    $packs = [Collections.Generic.List[object]]::new()
    foreach ($family in @($Files.family | Sort-Object -Unique)) {
        $groups = @($Files | Where-Object family -eq $family | Group-Object group | Sort-Object Name)
        $number = 0
        $current = $null
        foreach ($group in $groups) {
            $size = [long](($group.Group | Measure-Object bytes -Sum).Sum)
            if ($size -gt $CapacityBytes) { throw "Indivisible group '$($group.Name)' exceeds shard budget ($size bytes)." }
            if ($null -eq $current -or $current.bytes + $size -gt $CapacityBytes) {
                $number++
                $id = if ($family -eq 'core') { 'core' } else { '{0}-{1:00}' -f $family, $number }
                if ($family -eq 'core' -and $number -gt 1) { throw 'Core exceeds shard budget; do not split gameplay code.' }
                $current = [pscustomobject]@{ id = $id; family = $family; bytes = [long]0; files = [Collections.Generic.List[object]]::new() }
                $packs.Add($current)
            }
            foreach ($file in @($group.Group | Sort-Object path)) { $current.files.Add($file) }
            $current.bytes += $size
        }
    }
    return @($packs)
}

function Get-WorkshopModelCompanions {
    param([string]$ContentRoot, [string]$Model)
    $path = ConvertTo-WorkshopPath $Model
    if ($path -notmatch '^models/zombiesim/[\w/-]+\.mdl$') { throw "Unexpected owned model path: $Model" }
    $base = $path.Substring(0, $path.Length - 4)
    foreach ($extension in '.mdl', '.vvd', '.dx90.vtx') {
        $file = "$base$extension"
        if (-not (Test-Path -LiteralPath (Join-Path $ContentRoot $file.Replace('/', '\')) -PathType Leaf)) {
            throw "Missing model companion: $file"
        }
        $file
    }
    foreach ($extension in '.phy', '.dx80.vtx', '.sw.vtx') {
        $file = "$base$extension"
        if (Test-Path -LiteralPath (Join-Path $ContentRoot $file.Replace('/', '\')) -PathType Leaf) { $file }
    }
}

function Write-WorkshopJson {
    param([string]$Path, [object]$Value)
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path)
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 14), [Text.UTF8Encoding]::new($false))
}

function Test-WorkshopStaging {
    param([string]$Directory, [object[]]$Files, [switch]$AllowAddonJson)
    foreach ($file in $Files) {
        $destination = Join-Path $Directory $file.path.Replace('/', '\')
        if (-not (Test-Path -LiteralPath $destination -PathType Leaf) -or
            (Get-Item -LiteralPath $destination).Length -ne $file.bytes -or
            (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256) {
            throw "Staged package hash/size mismatch: $($file.path)"
        }
    }
    $expected = @{}
    foreach ($file in $Files) { $expected[$file.path] = $true }
    foreach ($file in Get-ChildItem -LiteralPath $Directory -Recurse -File) {
        $relative = ConvertTo-WorkshopPath $file.FullName.Substring($Directory.Length + 1)
        if (-not $expected.ContainsKey($relative) -and -not ($AllowAddonJson -and $relative -eq 'addon.json')) {
            throw "Unexpected file in staged package: $relative"
        }
    }
}

function Invoke-WorkshopArchive {
    param([string]$Gmad, [string]$Directory, [string]$Output, [object[]]$Files, [long]$MaximumBytes)
    if (-not (Test-Path -LiteralPath $Gmad -PathType Leaf)) { throw "gmad.exe not found: $Gmad" }
    if (Test-Path -LiteralPath $Output) { throw "Archive already exists: $Output" }
    & $Gmad create -folder $Directory -out $Output *> "$Output.create.log"
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Output -PathType Leaf)) {
        throw "gmad create failed; inspect $Output.create.log`n$((Get-Content -LiteralPath "$Output.create.log" -Tail 12) -join "`n")"
    }
    if ((Get-Item -LiteralPath $Output).Length -gt $MaximumBytes) { throw "Packed GMA exceeds byte budget: $Output" }
    $verification = Join-Path (Split-Path -Parent $Output) ('v-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Item -ItemType Directory -Path $verification
    try {
        & $Gmad extract -file $Output -out $verification *> "$Output.extract.log"
        if ($LASTEXITCODE -ne 0) { throw "gmad extract failed; inspect $Output.extract.log`n$((Get-Content -LiteralPath "$Output.extract.log" -Tail 12) -join "`n")" }
        Test-WorkshopStaging $verification @($Files | Where-Object path -ne 'addon.json') -AllowAddonJson
    } finally { Remove-Item -LiteralPath $verification -Recurse -Force }
}

Export-ModuleMember -Function ConvertTo-WorkshopPath, Get-WorkshopTextHash, Add-WorkshopFile,
    Split-WorkshopPackages, Get-WorkshopModelCompanions, Write-WorkshopJson, Test-WorkshopStaging, Invoke-WorkshopArchive, Resolve-WorkshopId
