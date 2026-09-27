param(
    [Parameter(Mandatory)]
    [ValidateSet('preview', 'city')]
    [string]$WorldProfile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile
$name = "zn_${WorldProfile}_start"
$source = Join-Path $projectRoot (Join-Path $profile.Settings.paths.launcherTemplateDirectory "$name.vmf")
$buildDirectory = Join-Path $projectRoot 'generated\launcher_build'
$gameDirectory = Split-Path -Parent (Split-Path -Parent $projectRoot)
$compilerDirectory = Join-Path (Split-Path -Parent $gameDirectory) 'bin'
$contentMaps = Join-Path $projectRoot $profile.Config.releaseMapDirectory
$gameMaps = Join-Path $gameDirectory 'maps'
$buildVmf = Join-Path $buildDirectory "$name.vmf"
$buildBsp = Join-Path $buildDirectory "$name.bsp"

if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Launcher VMF not found: $source" }
foreach ($stage in @('vbsp', 'vvis', 'vrad')) {
    if (-not (Test-Path -LiteralPath (Join-Path $compilerDirectory "$stage.exe") -PathType Leaf)) {
        throw "Missing $stage compiler in $compilerDirectory"
    }
}
[System.IO.Directory]::CreateDirectory($buildDirectory) | Out-Null
Copy-Item -LiteralPath $source -Destination $buildVmf -Force
if (Test-Path -LiteralPath $buildBsp) { Remove-Item -LiteralPath $buildBsp -Force }

foreach ($stage in @('vbsp', 'vvis', 'vrad')) {
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = Join-Path $compilerDirectory "$stage.exe"
    $start.Arguments = "-game `"$gameDirectory`" `"$([System.IO.Path]::ChangeExtension($buildVmf, $null))`""
    $start.WorkingDirectory = $buildDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw "Could not start $stage for $name" }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $output = $stdout.Result + [Environment]::NewLine + $stderr.Result
        $log = Join-Path $buildDirectory "$name.$stage.log"
        [System.IO.File]::WriteAllText($log, $output)
        $leaked = $output -match '(?im)\bleaked!|\*\*\*\s*leaked\b|^\s*leaked\s*$'
        if ($process.ExitCode -ne 0 -or $leaked) {
            throw "$stage failed for $name (exit $($process.ExitCode), leaked=$leaked); see $log"
        }
        if (-not (Test-Path -LiteralPath $buildBsp -PathType Leaf)) { throw "$stage produced no BSP for $name; see $log" }
        Write-Output "$name $stage passed; log: $log"
    } finally {
        $process.Dispose()
    }
}

$hash = (Get-FileHash -LiteralPath $buildBsp -Algorithm SHA256).Hash
foreach ($directory in @($contentMaps, $gameMaps)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    $destination = Join-Path $directory "$name.bsp"
    Copy-Item -LiteralPath $buildBsp -Destination $destination -Force
    $stagedHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    if ($stagedHash -ne $hash) { throw "Launcher BSP staging hash mismatch: $destination" }
    Write-Output "$destination SHA256 $stagedHash"
}
