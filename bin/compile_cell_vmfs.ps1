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
    [int]$MaxParallelProcesses = 0,
    [switch]$Force,
    [switch]$Fast,
    [switch]$Final,
    [string]$WorldProfile = '',
    [switch]$Preview,
    [switch]$VBSPOnly,
    [switch]$SkipVBSP,
    [switch]$PrioritizePortalCost,
    [switch]$SkipVis,
    [switch]$SkipRad,
    [switch]$FinalizeWithIncomplete,
    [switch]$WhatIf,
    [string]$SettingsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ps_progress_utils.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'vmf_source_dependencies.psm1') -Force
Write-ZMProgress -Activity 'Compiling cell recipes' -Status 'Preparing compiler profile and queued map list.' -PercentComplete 1 -Step 'setup'

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

function Get-PortalCost {
    param([string]$PortalPath)

    if (-not (Test-Path -LiteralPath $PortalPath -PathType Leaf)) {
        throw "Portal-cost ordering requires a .prt file: $PortalPath"
    }
    $header = @(Get-Content -LiteralPath $PortalPath -TotalCount 3)
    if ($header.Count -lt 3 -or $header[0].Trim() -ne 'PRT1' -or $header[1].Trim() -notmatch '^\d+$' -or $header[2].Trim() -notmatch '^\d+$') {
        throw "Portal-cost ordering requires a valid PRT1 portal file: $PortalPath"
    }

    return [pscustomobject]@{
        portalClusters = [int]$header[1].Trim()
        portals = [int]$header[2].Trim()
    }
}

function Test-CompletedCompilerStage {
    param(
        [string]$StageLogPath,
        [string]$InputPath
    )

    if (-not (Test-Path -LiteralPath $StageLogPath -PathType Leaf) -or -not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
        return $false
    }
    if ((Get-Item -LiteralPath $StageLogPath).LastWriteTimeUtc -lt (Get-Item -LiteralPath $InputPath).LastWriteTimeUtc) {
        return $false
    }

    $stageLog = Get-Content -LiteralPath $StageLogPath -Raw
    return $stageLog -match '(?m)\b(?:\d+ minutes, )?\d+ seconds elapsed\s*$'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$worldGenerationProfile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -Preview:$Preview -SettingsPath $SettingsPath
$generatorSettings = $worldGenerationProfile.Settings
$profileSettings = $worldGenerationProfile.Config
$compilationSettings = Get-SettingsValue $generatorSettings 'compilation' @{}
if ($Fast -and $Final) { throw 'Fast and Final cannot be selected together.' }
if (-not $Fast -and -not $Final) {
    if ($worldGenerationProfile.Name -eq 'preview') { $Fast = $true } else { $Final = $true }
}
$stagePresetName = if ($Fast) { 'fast' } else { 'final' }
$stagePresets = Get-SettingsValue $compilationSettings 'stagePresets' @{}
if (-not $stagePresets.ContainsKey($stagePresetName)) {
    throw "Compiler preset '$stagePresetName' is missing under compilation.stagePresets."
}
$stagePreset = $stagePresets[$stagePresetName]
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
$configuredParallelProcesses = [int](Get-SettingsValue $compilationSettings 'maxParallelProcesses' 4)
if ($MaxParallelProcesses -lt 1) { $MaxParallelProcesses = $configuredParallelProcesses }
if ($MaxParallelProcesses -lt 1) { throw 'compilation.maxParallelProcesses and MaxParallelProcesses must be at least 1.' }
if ($VBSPOnly) {
    $SkipVis = $true
    $SkipRad = $true
}
if ($VBSPOnly -and $SkipVBSP) {
    throw 'VBSPOnly and SkipVBSP cannot be used together.'
}
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
    $SourceDirectory = Join-Path $projectRoot $profileSettings.cellDirectory
}
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
    $BuildDirectory = Join-Path $projectRoot $profileSettings.buildDirectory
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
if ($PrioritizePortalCost) {
    if (-not $SkipVBSP) {
        throw 'PrioritizePortalCost requires SkipVBSP because VBSP creates the portal files after compilation begins.'
    }
    $sourceMaps = @($sourceMaps | ForEach-Object {
        $portalPath = Join-Path $BuildDirectory ([System.IO.Path]::ChangeExtension($_.Name, '.prt'))
        $portalCost = Get-PortalCost $portalPath
        [pscustomobject]@{
            sourceMap = $_
            portalClusters = $portalCost.portalClusters
            portals = $portalCost.portals
        }
    } | Sort-Object @{ Expression = { $_.portals }; Descending = $true }, @{ Expression = { $_.portalClusters }; Descending = $true }, @{ Expression = { $_.sourceMap.Name }; Descending = $false } | ForEach-Object { $_.sourceMap })
    Write-Output "Prioritized $($sourceMaps.Count) maps by portal count, then portal-cluster count."
}

$logDirectory = Join-Path $BuildDirectory 'logs'
function Start-SourceCompiler {
    param(
        [string]$Stage,
        [string]$Executable,
        [string[]]$Arguments,
        [string]$LogPath,
        [object]$Work,
        [object]$StageRecord
    )

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
    return [pscustomobject]@{
        work = $Work
        stage = $Work.mapStages[$Work.stageIndex]
        stageRecord = $StageRecord
        process = $process
        stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        startedUtc = [DateTime]::UtcNow
        deferred = $false
        log = $LogPath
        errorLog = $errorLogPath
    }
}

$stages = @()
if (-not $SkipVBSP) { $stages += [pscustomobject]@{ name = 'vbsp'; timeoutSeconds = $VbspTimeoutSeconds } }
if (-not $SkipVis) { $stages += [pscustomobject]@{ name = 'vvis'; timeoutSeconds = $VvisTimeoutSeconds } }
if (-not $SkipRad) { $stages += [pscustomobject]@{ name = 'vrad'; timeoutSeconds = $VradTimeoutSeconds } }
if ($stages.Count -eq 0) { throw 'At least one compiler stage must be enabled.' }
$compiled = 0
$skipped = 0
$compileStartedUtc = [DateTime]::UtcNow
$compileStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$mapResults = [System.Collections.Generic.List[object]]::new()
$deferredStages = [System.Collections.Generic.List[object]]::new()
$mapWorkQueue = [System.Collections.Generic.List[object]]::new()
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
    if ($SkipVBSP) {
        $portalPath = [System.IO.Path]::ChangeExtension($buildVmfPath, '.prt')
        if (-not (Test-Path -LiteralPath $buildBspPath -PathType Leaf) -or -not (Test-Path -LiteralPath $portalPath -PathType Leaf)) {
            throw "SkipVBSP requires existing BSP and portal files: $buildBspPath; $portalPath"
        }
        $needsCompile = $true
    } else {
        $needsCompile = $Force -or -not (Test-Path -LiteralPath $buildBspPath) -or (Get-VmfSourceWriteTimeUtc $sourceMap.FullName) -gt (Get-Item -LiteralPath $buildBspPath).LastWriteTimeUtc
    }
    if (-not $needsCompile) {
        $skipped++
        $mapRecord.status = 'skipped-current'
        $mapResults.Add($mapRecord)
        Write-Output "Skipped current BSP: $($sourceMap.Name); $remainingMaps maps left"
        continue
    }

    if (-not $WhatIf -and -not $SkipVBSP) {
        [System.IO.Directory]::CreateDirectory($BuildDirectory) | Out-Null
        [System.IO.Directory]::CreateDirectory($logDirectory) | Out-Null
        Copy-Item -LiteralPath $sourceMap.FullName -Destination $buildVmfPath -Force
    }

    $mapBaseName = [System.IO.Path]::GetFileNameWithoutExtension($sourceMap.Name)
    $mapStages = @($stages)
    if ($SkipVBSP -and -not $Force) {
        $vvisLogPath = Join-Path $logDirectory "$mapBaseName.vvis.log"
        $vradLogPath = Join-Path $logDirectory "$mapBaseName.vrad.log"
        $vvisIsCurrent = $SkipVis -or (Test-CompletedCompilerStage $vvisLogPath $portalPath)
        $vradIsCurrent = $SkipRad -or ($vvisIsCurrent -and (Test-CompletedCompilerStage $vradLogPath $vvisLogPath))
        $mapStages = @($stages | Where-Object {
            ($_.name -ne 'vvis' -or -not $vvisIsCurrent) -and
            ($_.name -ne 'vrad' -or -not $vradIsCurrent)
        })
    }
    if ($mapStages.Count -eq 0) {
        $skipped++
        $mapRecord.status = 'skipped-current'
        $mapResults.Add($mapRecord)
        Write-Output "Skipped current VVIS/VRAD: $($sourceMap.Name); $remainingMaps maps left"
        continue
    }

    $mapResults.Add($mapRecord)
    $mapWorkQueue.Add([pscustomobject]@{
        sourceMap = $sourceMap
        mapNumber = $mapNumber
        buildBspPath = $buildBspPath
        mapStages = $mapStages
        stageIndex = 0
        mapRecord = $mapRecord
        stageRecords = $stageRecords
    })
}

function Start-MapCompilerStage {
    param([object]$Work)

    $stage = $Work.mapStages[$Work.stageIndex]
    $argumentTemplate = if ($stagePreset.ContainsKey($stage.name)) {
        @($stagePreset[$stage.name])
    } else {
        @($compilerProfileSettings.arguments[$stage.name])
    }
    $tokens = @{ gameDirectory = $GameDirectory; mapVmf = (Join-Path $BuildDirectory $Work.sourceMap.Name); mapBsp = $Work.buildBspPath }
    $arguments = @(Expand-CompilerArguments $argumentTemplate $tokens)
    $mapBaseName = [System.IO.Path]::GetFileNameWithoutExtension($Work.sourceMap.Name)
    $stageLogPath = Join-Path $logDirectory "$mapBaseName.$($stage.name).log"
    $stageRecord = [ordered]@{ stage = $stage.name; status = 'running'; log = $stageLogPath; errorLog = "$stageLogPath.stderr" }
    $Work.stageRecords.Add($stageRecord)
    Write-Host "Compiling $($Work.mapNumber)/$($sourceMaps.Count): $($Work.sourceMap.Name) [$($stage.name); preset=$stagePresetName; pool=$MaxParallelProcesses]"
    return Start-SourceCompiler $stage.name $compilerPaths[$stage.name] $arguments $stageLogPath $Work $stageRecord
}

if ($WhatIf) {
    foreach ($work in $mapWorkQueue) {
        for ($stageIndex = 0; $stageIndex -lt $work.mapStages.Count; $stageIndex++) {
            $work.stageIndex = $stageIndex
            $stage = $work.mapStages[$stageIndex]
            $argumentTemplate = if ($stagePreset.ContainsKey($stage.name)) { @($stagePreset[$stage.name]) } else { @($compilerProfileSettings.arguments[$stage.name]) }
            $tokens = @{ gameDirectory = $GameDirectory; mapVmf = (Join-Path $BuildDirectory $work.sourceMap.Name); mapBsp = $work.buildBspPath }
            $arguments = @(Expand-CompilerArguments $argumentTemplate $tokens)
            Write-Host "WhatIf: $($compilerPaths[$stage.name]) $($arguments -join ' ')"
            $stageLogPath = Join-Path $logDirectory "$([System.IO.Path]::GetFileNameWithoutExtension($work.sourceMap.Name)).$($stage.name).log"
            $work.stageRecords.Add([ordered]@{ stage = $stage.name; status = 'what-if'; log = $stageLogPath; errorLog = "$stageLogPath.stderr" })
        }
        $work.mapRecord.status = 'what-if'
        $compiled++
    }
} else {
    [System.IO.Directory]::CreateDirectory($BuildDirectory) | Out-Null
    [System.IO.Directory]::CreateDirectory($logDirectory) | Out-Null
    $activeSlots = [System.Collections.Generic.List[object]]::new()
    $nextWorkIndex = 0

    while ($nextWorkIndex -lt $mapWorkQueue.Count -or @($activeSlots | Where-Object { -not $_.deferred }).Count -gt 0) {
        while ($nextWorkIndex -lt $mapWorkQueue.Count -and $activeSlots.Count -lt $MaxParallelProcesses) {
            $work = $mapWorkQueue[$nextWorkIndex]
            $nextWorkIndex++
            $activeSlots.Add((Start-MapCompilerStage $work))
        }

        $slotSnapshot = @($activeSlots.ToArray())
        foreach ($slot in $slotSnapshot) {
            if ($slot.process.HasExited) {
                $slot.process.WaitForExit()
                $slot.process.Refresh()
                $slot.stopwatch.Stop()
                $slot.stageRecord.exitCode = $slot.process.ExitCode
                $slot.stageRecord.durationSeconds = [Math]::Round($slot.stopwatch.Elapsed.TotalSeconds, 1)
                if ($slot.deferred) {
                    $deferredResult = $slot.deferredResult
                    $slot.stageRecord.durationSeconds = [Math]::Round(([DateTime]::UtcNow - $slot.startedUtc).TotalSeconds, 1)
                    if ($slot.process.ExitCode -eq 0 -and $deferredResult.stageIndex -eq ($deferredResult.stageCount - 1)) {
                        $slot.stageRecord.status = 'completed-after-timeout'
                        $slot.work.mapRecord.status = 'completed-after-timeout'
                        $compiled++
                    } elseif ($slot.process.ExitCode -eq 0) {
                        $slot.stageRecord.status = 'completed-after-timeout'
                        $slot.work.mapRecord.status = 'incomplete-after-timeout'
                    } else {
                        $slot.stageRecord.status = 'failed-after-timeout'
                        $slot.work.mapRecord.status = 'failed'
                    }
                    $deferredResult.finalized = $true
                    $slot.process.Dispose()
                    [void]$activeSlots.Remove($slot)
                    continue
                }
                if ($slot.process.ExitCode -ne 0) {
                    $slot.stageRecord.status = 'failed'
                    $slot.work.mapRecord.status = 'failed'
                    Write-Warning "$($slot.work.sourceMap.Name) [$($slot.stage.name)] failed with exit code $($slot.process.ExitCode)."
                    $slot.process.Dispose()
                    [void]$activeSlots.Remove($slot)
                    continue
                }
                if ($slot.stage.name -eq 'vbsp' -and -not (Test-Path -LiteralPath $slot.work.buildBspPath -PathType Leaf)) {
                    $slot.stageRecord.status = 'failed-no-bsp'
                    $slot.work.mapRecord.status = 'failed'
                    Write-Warning "$($slot.work.sourceMap.Name) completed VBSP without creating its expected BSP."
                    $slot.process.Dispose()
                    [void]$activeSlots.Remove($slot)
                    continue
                }

                $slot.stageRecord.status = 'completed'
                $slot.work.stageIndex++
                if ($slot.work.stageIndex -ge $slot.work.mapStages.Count) {
                    $slot.work.mapRecord.status = 'completed'
                    $compiled++
                    $slot.process.Dispose()
                    [void]$activeSlots.Remove($slot)
                } else {
                    $replacementSlot = Start-MapCompilerStage $slot.work
                    $slot.process.Dispose()
                    $slotIndex = $activeSlots.IndexOf($slot)
                    $activeSlots[$slotIndex] = $replacementSlot
                }
                continue
            }

            if (-not $slot.deferred -and $slot.stopwatch.Elapsed.TotalSeconds -ge $slot.stage.timeoutSeconds) {
                $slot.stopwatch.Stop()
                $slot.stageRecord.status = 'deferred'
                $slot.stageRecord.timeoutSeconds = $slot.stage.timeoutSeconds
                $slot.stageRecord.durationSeconds = [Math]::Round($slot.stopwatch.Elapsed.TotalSeconds, 1)
                $slot.work.mapRecord.status = 'deferred'
                $deferredResult = [pscustomobject]@{
                    slot = $slot
                    mapRecord = $slot.work.mapRecord
                    stageRecord = $slot.stageRecord
                    stageIndex = $slot.work.stageIndex
                    stageCount = $slot.work.mapStages.Count
                    finalized = $false
                }
                $slot.deferred = $true
                $slot.deferredResult = $deferredResult
                $deferredStages.Add($deferredResult)
                Write-Warning "Deferred $($slot.work.sourceMap.Name) [$($slot.stage.name)] after $($slot.stage.timeoutSeconds)s; remaining maps continue."
            }
        }

        if ($activeSlots.Count -gt 0 -or $nextWorkIndex -lt $mapWorkQueue.Count) {
            $remainingQueue = $mapWorkQueue.Count - $nextWorkIndex
            Write-Progress -Activity "Compiling $CompilerProfile cell recipes" -Status "$($activeSlots.Count) active; $remainingQueue queued; $($deferredStages.Count) deferred; $compiled completed" -PercentComplete ([int](($compiled + $skipped) / [double]$sourceMaps.Count * 100))
            Start-Sleep -Milliseconds $progressRefreshMilliseconds
        }
    }
}

if ($deferredStages.Count -gt 0 -and -not $WhatIf) {
    Write-Warning "Waiting up to $DeferredGraceSeconds seconds for $($deferredStages.Count) deferred compiler stage(s)."
    $graceStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($graceStopwatch.Elapsed.TotalSeconds -lt $DeferredGraceSeconds) {
        $runningDeferredStages = @($deferredStages | Where-Object { -not $_.finalized -and -not $_.slot.process.HasExited })
        if ($runningDeferredStages.Count -eq 0) { break }
        $remainingGraceSeconds = [math]::Ceiling($DeferredGraceSeconds - $graceStopwatch.Elapsed.TotalSeconds)
        Write-Progress -Activity 'Waiting for deferred compiler stages' -Status "$($runningDeferredStages.Count) stages still running; $remainingGraceSeconds seconds of grace remaining" -PercentComplete ([int](($graceStopwatch.Elapsed.TotalSeconds / $DeferredGraceSeconds) * 100))
        foreach ($deferredStage in $runningDeferredStages) { $deferredStage.slot.process.WaitForExit($progressRefreshMilliseconds) | Out-Null }
    }
    foreach ($deferredStage in $deferredStages) {
        if ($deferredStage.finalized) { continue }
        if (-not $deferredStage.slot.process.HasExited) { continue }
        $deferredStage.slot.process.WaitForExit()
        $deferredStage.slot.process.Refresh()
        $elapsedSeconds = [math]::Round(([DateTime]::UtcNow - $deferredStage.slot.startedUtc).TotalSeconds, 1)
        $deferredStage.stageRecord.exitCode = $deferredStage.slot.process.ExitCode
        $deferredStage.stageRecord.durationSeconds = $elapsedSeconds
        if ($deferredStage.slot.process.ExitCode -eq 0 -and $deferredStage.stageIndex -eq ($deferredStage.stageCount - 1)) {
            $deferredStage.stageRecord.status = 'completed-after-timeout'
            $deferredStage.mapRecord.status = 'completed-after-timeout'
            $compiled++
        } elseif ($deferredStage.slot.process.ExitCode -eq 0) {
            $deferredStage.stageRecord.status = 'completed-after-timeout'
            $deferredStage.mapRecord.status = 'incomplete-after-timeout'
        } else {
            $deferredStage.stageRecord.status = 'failed-after-timeout'
            $deferredStage.mapRecord.status = 'failed'
        }
        $deferredStage.finalized = $true
        $deferredStage.slot.process.Dispose()
    }
}

Write-Progress -Activity "Compiling $CompilerProfile cell recipes" -Completed
$compileStopwatch.Stop()
$incompleteResults = @($mapResults | Where-Object { $_.status -in @('deferred', 'incomplete-after-timeout') })
$failedResults = @($mapResults | Where-Object { $_.status -eq 'failed' })
$reportPath = Join-Path $BuildDirectory 'compile-report.json'
$report = [ordered]@{
    schemaVersion = 1
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    startedUtc = $compileStartedUtc.ToString('o')
    durationSeconds = [Math]::Round($compileStopwatch.Elapsed.TotalSeconds, 1)
    compilerProfile = $CompilerProfile
    preview = ($worldGenerationProfile.Name -eq 'preview')
    stagePreset = $stagePresetName
    maxParallelProcesses = $MaxParallelProcesses
    threadThrottle = 'The installed stock compilers expose no numeric thread-count option; concurrency is bounded by the process pool.'
    stages = @($stages | ForEach-Object { $_.name })
    prioritizedByPortalCost = [bool]$PrioritizePortalCost
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
Write-Output "Source VMFs: $($sourceMaps.Count); compiled: $compiled; skipped current: $skipped; failed: $($failedResults.Count); incomplete: $($incompleteResults.Count); preset: $stagePresetName; parallel processes: $MaxParallelProcesses; report: $reportPath"
if (($failedResults.Count -gt 0 -or $incompleteResults.Count -gt 0) -and -not $FinalizeWithIncomplete) {
    throw "Compilation is incomplete. Failed maps: $($failedResults.Count); still-running or unfinished maps: $($incompleteResults.Count). Review $reportPath, then rerun or use -FinalizeWithIncomplete to end without waiting further."
}