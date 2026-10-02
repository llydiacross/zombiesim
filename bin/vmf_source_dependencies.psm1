Set-StrictMode -Version Latest

# A recipe VMF only references its tiles through func_instance, so a tile edit leaves the
# recipe text unchanged. Compile staleness must use the newest write time across the VMF
# and every instance file it references, recursively.
$script:InstanceWriteTimeCache = @{}

function Get-VmfInstancePaths {
    param([Parameter(Mandatory)][string]$VmfPath)

    $vmfDirectory = Split-Path -Parent $VmfPath
    $content = [System.IO.File]::ReadAllText($VmfPath)
    $instanceMatches = [regex]::Matches($content, '"file"\s+"(?<file>[^"]+\.vmf)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $paths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($instanceMatch in $instanceMatches) {
        $relativePath = $instanceMatch.Groups['file'].Value.Replace('/', '\')
        [void]$paths.Add([System.IO.Path]::GetFullPath([System.IO.Path]::Combine($vmfDirectory, $relativePath)))
    }
    return @($paths)
}

function Get-InstanceTreeWriteTimeUtc {
    param(
        [Parameter(Mandatory)][string]$VmfPath,
        [hashtable]$Visiting = @{}
    )

    $key = $VmfPath.ToLowerInvariant()
    if ($script:InstanceWriteTimeCache.ContainsKey($key)) { return $script:InstanceWriteTimeCache[$key] }
    if (-not (Test-Path -LiteralPath $VmfPath -PathType Leaf)) { return [DateTime]::MinValue }
    if ($Visiting.ContainsKey($key)) { return [DateTime]::MinValue }
    $Visiting[$key] = $true

    $newest = (Get-Item -LiteralPath $VmfPath).LastWriteTimeUtc
    foreach ($instancePath in (Get-VmfInstancePaths $VmfPath)) {
        $instanceTime = Get-InstanceTreeWriteTimeUtc -VmfPath $instancePath -Visiting $Visiting
        if ($instanceTime -gt $newest) { $newest = $instanceTime }
    }
    $Visiting.Remove($key)
    $script:InstanceWriteTimeCache[$key] = $newest
    return $newest
}

function Get-VmfSourceWriteTimeUtc {
    param([Parameter(Mandatory)][string]$VmfPath)

    return Get-InstanceTreeWriteTimeUtc -VmfPath ([System.IO.Path]::GetFullPath($VmfPath))
}

function Write-TextFileIfChanged {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        if ([System.IO.File]::ReadAllText($Path) -ceq $Content) { return $false }
    }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
    return $true
}

function Copy-FileIfChanged {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        $sourceItem = Get-Item -LiteralPath $Source
        $destinationItem = Get-Item -LiteralPath $Destination
        if ($sourceItem.Length -eq $destinationItem.Length -and
            (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash) {
            return $false
        }
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    return $true
}

Export-ModuleMember -Function Get-VmfSourceWriteTimeUtc, Write-TextFileIfChanged, Copy-FileIfChanged
