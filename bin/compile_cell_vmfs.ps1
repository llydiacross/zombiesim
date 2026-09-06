param(
    [string]$SourceDirectory = '',
    [string]$BuildDirectory = '',
    [string]$GameDirectory = '',
    [string]$CompilerDirectory = '',
    [string]$CompilerProfile = '',
    [string[]]$MapFilename = @(),
    [int]$VbspTimeoutSeconds = 0,
    [int]$VvisTimeoutSeconds = 0,
    [int]$VradTimeoutSeconds = 0,
    [int]$DeferredGraceSeconds = 0,
    [switch]$Force,
    [switch]$Preview,
    [switch]$VBSPOnly,
    [switch]$SkipVis,
    [switch]$SkipRad,
    [switch]$FinalizeWithIncomplete,
    [switch]$WhatIf,
    [string]$SettingsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SettingsValue {
    param([hashtable]$Settings, [string]$Name, [object]$Fallback)

    if ($Settings.ContainsKey($Name)) { return $Settings[$Name] }
    return $Fallback
}

function Quote-ProcessArgument {
    param([string]$Value)

    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Expand-CompilerArguments {
    param([object[]]$Template, [hashtable]$Tokens)

    return @($Template | ForEach-Object {
        $value = [string]$_
        foreach ($token in $Tokens.Keys) { $value = $value.Replace("{$token}", [string]$Tokens[$token]) }
        $value
    })
}

function Resolve-CompilerExecutable {
    param([string]$ExecutableName, [string]$ToolDirectory)

    if ([System.IO.Path]::IsPathRooted($ExecutableName)) { return $ExecutableName }
    return Join-Path $ToolDirectory $ExecutableName
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$generatorSettings = & (Join-Path $PSScriptRoot 'import_generator_settings.ps1') -SettingsPath $SettingsPath
$compilationSettings = Get-SettingsValue $generatorSettings 'compilation' @{}
if ([string]::IsNullOrWhiteSpace($CompilerProfile)) { $CompilerProfile = [string](Get-SettingsValue $compilationSettings 'activeProfile' 'stock-gmod') }
if (-not $compilationSettings.ContainsKey('profiles') -or -not $compilationSettings.profiles.ContainsKey($CompilerProfile)) {
    throw "Unknown compiler profile '$CompilerProfile'. Add it under compilation.profiles in generator-settings.json."
}
$compilerProfileSettings = $compilationSettings.profiles[$CompilerProfile]
$timeoutSettings = Get-SettingsValue $compilationSettings 'stageTimeoutSeconds' @{}
if ($VbspTimeoutSeconds -lt 1) { $VbspTimeoutSeconds = [int](Get-SettingsValue $timeoutSettings 'vbsp' 300) }
if ($VvisTimeoutSeconds -lt 1) { $VvisTimeoutSeconds = [int](Get-SettingsValue $timeoutSettings 'vvis' 900) }
if ($VradTimeoutSeconds -lt 1) { $VradTimeoutSeconds = [int](Get-SettingsValue $timeoutSettings 'vrad' 1800) }
if ($DeferredGraceSeconds -lt 0) { throw 'DeferredGraceSeconds cannot be negative.' }
if ($DeferredGraceSeconds -eq 0) { $DeferredGraceSeconds = [int](Get-SettingsValue $compilationSettings 'deferredGraceSeconds' 300) }
$progressRefreshMilliseconds = [int](Get-SettingsValue $compilationSettings 'progressRefreshMilliseconds' 1000)
if ($progressRefreshMilliseconds -lt 100) { throw 'compilation.progressRefreshMilliseconds must be at least 100.' }
if ($VBSPOnly) {
    $SkipVis = $true
    $SkipRad = $true
}
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
    $sourceDirectorySetting = if ($Preview) { $generatorSettings.paths.previewCellDirectory } else { $generatorSettings.paths.cellDirectory }
    $SourceDirectory = Join-Path $projectRoot $sourceDirectorySetting
}
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
    $buildDirectoryKey = if ($Preview) { 'previewBuildDirectory' } else { 'buildDirectory' }
    $buildDirectoryFallback = if ($Preview) { 'maps/build_preview' } else { 'maps/build' }
    $buildDirectorySetting = if ($generatorSettings.paths.ContainsKey($buildDirectoryKey)) { $generatorSettings.paths[$buildDirectoryKey] } else { $buildDirectoryFallback }
    $BuildDirectory = Join-Path $projectRoot $buildDirectorySetting
}
if ([string]::IsNullOrWhiteSpace($GameDirectory)) {
    $GameDirectory = Split-Path -Parent (Split-Path -Parent $projectRoot)
}
if ([string]::IsNullOrWhiteSpace($CompilerDirectory)) {
    $configuredToolDirectory = [string](Get-SettingsValue $compilerProfileSettings 'toolDirectory' '')
    if ([string]::IsNullOrWhiteSpace($configuredToolDirectory)) {
        $CompilerDirectory = Join-Path (Split-Path -Parent $GameDirectory) 'bin'
    } elseif ([System.IO.Path]::IsPathRooted($configuredToolDirectory)) {
        $CompilerDirectory = $configuredToolDirectory
    } else {
        $CompilerDirectory = Join-Path $projectRoot $configuredToolDirectory
    }
}

if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
    throw "Cell source directory was not found: $SourceDirectory"
}
if (-not (Test-Path -LiteralPath (Join-Path $GameDirectory 'gameinfo.txt') -PathType Leaf)) {
    throw "Garry's Mod game directory must contain gameinfo.txt: $GameDirectory"
}

$SourceDirectory = (Resolve-Path -LiteralPath $SourceDirectory).Path.TrimEnd('\')
$sourceMapsDirectory = Split-Path -Parent $SourceDirectory
$BuildDirectory = [System.IO.Path]::GetFullPath($BuildDirectory).TrimEnd('\')
if (-not [string]::Equals((Split-Path -Parent $BuildDirectory), $sourceMapsDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "BuildDirectory must be a sibling of SourceDirectory so VMF instance paths remain valid. Expected a folder under: $sourceMapsDirectory"
}

$compilerPaths = @{}
foreach ($stageName in @('vbsp', 'vvis', 'vrad')) {
    if (-not $compilerProfileSettings.executables.ContainsKey($stageName)) {
        throw "Compiler profile '$CompilerProfile' is missing executables.$stageName."
    }
    if (-not $compilerProfileSettings.arguments.ContainsKey($stageName)) {
        throw "Compiler profile '$CompilerProfile' is missing arguments.$stageName."
    }
    $compilerPaths[$stageName] = Resolve-CompilerExecutable ([string]$compilerProfileSettings.executables[$stageName]) $CompilerDirectory
    if (-not (Test-Path -LiteralPath $compilerPaths[$stageName] -PathType Leaf)) {
        throw "${stageName} compiler was not found: $($compilerPaths[$stageName])"
    }
}

if ($MapFilename.Count -gt 0) {
    $sourceMaps = @(foreach ($filename in ($MapFilename | Sort-Object -Unique)) {
        if ([System.IO.Path]::GetFileName($filename) -ne $filename -or [System.IO.Path]::GetExtension($filename) -ine '.vmf') {
            throw "MapFilename must be a .vmf filename without a path: $filename"
        }
        $sourcePath = Join-Path $SourceDirectory $filename
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Requested source VMF was not found: $sourcePath"
        }
        Get-Item -LiteralPath $sourcePath
    })
} else {
    $sourceMaps = @(Get-ChildItem -LiteralPath $SourceDirectory -Filter '*.vmf' -File | Sort-Object Name)
}
if ($sourceMaps.Count -eq 0) {
    throw "No source VMFs were found in: $SourceDirectory"
}

$logDirectory = Join-Path $BuildDirectory 'logs'
function Invoke-SourceCompiler {
    param(
        [string]$Stage,
        [string]$Executable,
        [string[]]$Arguments,
        [string]$LogPath,
        [int]$TimeoutSeconds,
        [int]$MapNumber,
        [int]$MapCount,
        [string]$MapName
    )

    if ($WhatIf) {
        Write-Host "WhatIf: ${Stage}: $Executable $($Arguments -join ' ')"
        return [pscustomobject]@{ status = 'what-if'; exitCode = 0; durationSeconds = 0; log = $LogPath; errorLog = "$LogPath.stderr" }
    }

    $errorLogPath = "$LogPath.stderr"
    $commandLine = "$(Quote-ProcessArgument $Executable) $(($Arguments | ForEach-Object { Quote-ProcessArgument $_ }) -join ' ') 1> $(Quote-ProcessArgument $LogPath) 2> $(Quote-ProcessArgument $errorLogPath)"
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $env:ComSpec
    $startInfo.Arguments = "/d /s /c `"$commandLine`""
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "Could not start ${Stage}: $Executable"
    }
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $process.HasExited -and $stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $process.WaitForExit($progressRefreshMilliseconds) | Out-Null
        $remainingMaps = $MapCount - $MapNumber
        $elapsedSeconds = [math]::Floor($stopwatch.Elapsed.TotalSeconds)
        $percentComplete = [int](($MapNumber - 1) / $MapCount * 100)
        Write-Progress -Activity "Compiling $CompilerProfile cell recipes" -Status "Map $MapNumber/${MapCount}: $MapName [$Stage $elapsedSeconds/$TimeoutSeconds s]; $remainingMaps maps left" -PercentComplete $percentComplete
    }

    if (-not $process.HasExited) {
        return [pscustomobject]@{ status = 'deferred'; process = $process; stage = $Stage; startedUtc = [DateTime]::UtcNow - $stopwatch.Elapsed; timeoutSeconds = $TimeoutSeconds; log = $LogPath; errorLog = $errorLogPath }
    }
    $process.WaitForExit()
    $process.Refresh()
    return [pscustomobject]@{ status = if ($process.ExitCode -eq 0) { 'completed' } else { 'failed' }; exitCode = $process.ExitCode; durationSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1); log = $LogPath; errorLog = $errorLogPath }
}

$stages = @([pscustomobject]@{ name = 'vbsp'; timeoutSeconds = $VbspTimeoutSeconds })
if (-not $SkipVis) { $stages += [pscustomobject]@{ name = 'vvis'; timeoutSeconds = $VvisTimeoutSeconds } }
if (-not $SkipRad) { $stages += [pscustomobject]@{ name = 'vrad'; timeoutSeconds = $VradTimeoutSeconds } }
$compiled = 0
$skipped = 0
$mapResults = [System.Collections.Generic.List[object]]::new()
$deferredStages = [System.Collections.Generic.List[object]]::new()
for ($mapIndex = 0; $mapIndex -lt $sourceMaps.Count; $mapIndex++) {
    $sourceMap = $sourceMaps[$mapIndex]
    $mapNumber = $mapIndex + 1
    $remainingMaps = $sourceMaps.Count - $mapNumber
    $buildVmfPath = Join-Path $BuildDirectory $sourceMap.Name
    $buildBspPath = [System.IO.Path]::ChangeExtension($buildVmfPath, '.bsp')
    $stageRecords = [System.Collections.Generic.List[object]]::new()
    $mapRecord = [ordered]@{ map = $sourceMap.Name; status = 'pending'; stages = $stageRecords }
    $percentComplete = [int](($mapIndex / $sourceMaps.Count) * 100)
    Write-Progress -Activity "Compiling $CompilerProfile cell recipes" -Status "Map $mapNumber/$($sourceMaps.Count): $($sourceMap.Name); $remainingMaps maps left" -PercentComplete $percentComplete
    $needsCompile = $Force -or -not (Test-Path -LiteralPath $buildBspPath) -or $sourceMap.LastWriteTimeUtc -gt (Get-Item -LiteralPath $buildBspPath).LastWriteTimeUtc
    if (-not $needsCompile) {
        $skipped++
        $mapRecord.status = 'skipped-current'
        $mapResults.Add($mapRecord)
        Write-Output "Skipped current BSP: $($sourceMap.Name); $remainingMaps maps left"
        continue
    }

    if (-not $WhatIf) {
        [System.IO.Directory]::CreateDirectory($BuildDirectory) | Out-Null
        [System.IO.Directory]::CreateDirectory($logDirectory) | Out-Null
        Copy-Item -LiteralPath $sourceMap.FullName -Destination $buildVmfPath -Force
    }

    $mapBaseName = [System.IO.Path]::GetFileNameWithoutExtension($sourceMap.Name)
    $mapDeferred = $false
    $mapFailed = $false
    for ($stageIndex = 0; $stageIndex -lt $stages.Count; $stageIndex++) {
        $stage = $stages[$stageIndex]
        $tokens = @{ gameDirectory = $GameDirectory; mapVmf = $buildVmfPath; mapBsp = $buildBspPath }
        $arguments = Expand-CompilerArguments @($compilerProfileSettings.arguments[$stage.name]) $tokens
        $stageLogPath = Join-Path $logDirectory "$mapBaseName.$($stage.name).log"
        Write-Output "Compiling $mapNumber/$($sourceMaps.Count): $($sourceMap.Name) [$($stage.name); $remainingMaps maps left]"
        $stageResult = Invoke-SourceCompiler $stage.name $compilerPaths[$stage.name] $arguments $stageLogPath $stage.timeoutSeconds $mapNumber $sourceMaps.Count $sourceMap.Name
        $stageRecord = [ordered]@{ stage = $stage.name; status = $stageResult.status; log = $stageResult.log; errorLog = $stageResult.errorLog }
        if ($stageResult.status -eq 'deferred') {
            $stageRecord.timeoutSeconds = $stageResult.timeoutSeconds
            $stageRecords.Add($stageRecord)
            $deferredStages.Add([pscustomobject]@{ result = $stageResult; mapRecord = $mapRecord; stageRecord = $stageRecord; stageIndex = $stageIndex; stageCount = $stages.Count })
            $mapDeferred = $true
            Write-Warning "Deferred $($sourceMap.Name) [$($stage.name)] after $($stage.timeoutSeconds)s; continuing with $remainingMaps maps left."
            break
        }
        $stageRecord.exitCode = $stageResult.exitCode
        $stageRecord.durationSeconds = $stageResult.durationSeconds
        $stageRecords.Add($stageRecord)
        if ($stageResult.status -eq 'failed') {
            $mapFailed = $true
            Write-Warning "$($sourceMap.Name) [$($stage.name)] failed with exit code $($stageResult.exitCode); continuing with $remainingMaps maps left."
            break
        }
        if (-not $WhatIf -and $stage.name -eq 'vbsp' -and -not (Test-Path -LiteralPath $buildBspPath -PathType Leaf)) {
            $stageRecord.status = 'failed-no-bsp'
            $mapFailed = $true
            Write-Warning "$($sourceMap.Name) completed VBSP without creating its expected BSP; continuing with $remainingMaps maps left."
            break
        }
    }
    if ($mapDeferred) { $mapRecord.status = 'deferred' }
    elseif ($mapFailed) { $mapRecord.status = 'failed' }
    else { $mapRecord.status = if ($WhatIf) { 'what-if' } else { 'completed' }; $compiled++ }
    $mapResults.Add($mapRecord)
}

if ($deferredStages.Count -gt 0 -and -not $WhatIf) {
    Write-Warning "Waiting up to $DeferredGraceSeconds seconds for $($deferredStages.Count) deferred compiler stage(s)."
    $graceStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($graceStopwatch.Elapsed.TotalSeconds -lt $DeferredGraceSeconds) {
        $runningDeferredStages = @($deferredStages | Where-Object { -not $_.result.process.HasExited })
        if ($runningDeferredStages.Count -eq 0) { break }
        $remainingGraceSeconds = [math]::Ceiling($DeferredGraceSeconds - $graceStopwatch.Elapsed.TotalSeconds)
        Write-Progress -Activity 'Waiting for deferred compiler stages' -Status "$($runningDeferredStages.Count) stages still running; $remainingGraceSeconds seconds of grace remaining" -PercentComplete ([int](($graceStopwatch.Elapsed.TotalSeconds / $DeferredGraceSeconds) * 100))
        foreach ($deferredStage in $runningDeferredStages) { $deferredStage.result.process.WaitForExit($progressRefreshMilliseconds) | Out-Null }
    }
    foreach ($deferredStage in $deferredStages) {
        if (-not $deferredStage.result.process.HasExited) { continue }
        $deferredStage.result.process.WaitForExit()
        $elapsedSeconds = [math]::Round(([DateTime]::UtcNow - $deferredStage.result.startedUtc).TotalSeconds, 1)
        $deferredStage.stageRecord.exitCode = $deferredStage.result.process.ExitCode
        $deferredStage.stageRecord.durationSeconds = $elapsedSeconds
        if ($deferredStage.result.process.ExitCode -eq 0 -and $deferredStage.stageIndex -eq ($deferredStage.stageCount - 1)) {
            $deferredStage.stageRecord.status = 'completed-after-timeout'
            $deferredStage.mapRecord.status = 'completed-after-timeout'
            $compiled++
        } elseif ($deferredStage.result.process.ExitCode -eq 0) {
            $deferredStage.stageRecord.status = 'completed-after-timeout'
            $deferredStage.mapRecord.status = 'incomplete-after-timeout'
        } else {
            $deferredStage.stageRecord.status = 'failed-after-timeout'
            $deferredStage.mapRecord.status = 'failed'
        }
    }
}

Write-Progress -Activity "Compiling $CompilerProfile cell recipes" -Completed
$incompleteResults = @($mapResults | Where-Object { $_.status -in @('deferred', 'incomplete-after-timeout') })
$failedResults = @($mapResults | Where-Object { $_.status -eq 'failed' })
$reportPath = Join-Path $BuildDirectory 'compile-report.json'
$report = [ordered]@{
    schemaVersion = 1
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    compilerProfile = $CompilerProfile
    preview = [bool]$Preview
    stages = @($stages | ForEach-Object { $_.name })
    sourceDirectory = $SourceDirectory
    buildDirectory = $BuildDirectory
    sourceMapCount = $sourceMaps.Count
    compiledCount = $compiled
    skippedCurrentCount = $skipped
    failedCount = $failedResults.Count
    incompleteCount = $incompleteResults.Count
    maps = @($mapResults)
}
if (-not $WhatIf) {
    [System.IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
}
Write-Output "Source VMFs: $($sourceMaps.Count); compiled: $compiled; skipped current: $skipped; failed: $($failedResults.Count); incomplete: $($incompleteResults.Count); report: $reportPath"
if (($failedResults.Count -gt 0 -or $incompleteResults.Count -gt 0) -and -not $FinalizeWithIncomplete) {
    throw "Compilation is incomplete. Failed maps: $($failedResults.Count); still-running or unfinished maps: $($incompleteResults.Count). Review $reportPath, then rerun or use -FinalizeWithIncomplete to end without waiting further."
}