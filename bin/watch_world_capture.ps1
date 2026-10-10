param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[\w-]+$')][string]$RunId,
    [int]$PollSeconds = 30,
    [switch]$StagePreview
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dataRoot = Join-Path (Split-Path (Split-Path $root -Parent) -Parent) 'data'
$statePath = Join-Path $dataRoot 'zombiesim\world_capture_state.json'
$heartbeatPath = Join-Path $dataRoot 'zombiesim\consolecommands.heartbeat.json'
$lastResults = -1
$lastAdvance = Get-Date
while ($true) {
    $state = Get-Content $statePath -Raw | ConvertFrom-Json
    if ($state.runId -ne $RunId) { throw "Different run replaced monitored checkpoint." }
    if ($state.completedResults -ne $lastResults) {
        $lastResults = $state.completedResults
        $lastAdvance = Get-Date
        Write-Output ("{0:u} run={1} phase={2} results={3}/{4} cell={5}/{6}" -f
            (Get-Date), $RunId, $state.phase, $lastResults, ($state.requiredCellCount * 2),
            $state.index, $state.queue.Count)
    }
    if (-not $state.active) {
        if ($state.phase -ne 'complete' -or -not $state.restorationVerified) {
            throw "Run stopped: $($state.phase). Check checkpoint error/restoration before retry."
        }
        if ($lastResults -ne ($state.requiredCellCount * 2)) { throw "Run is partial; full import refused." }
        $runPath = Join-Path $dataRoot ("zombiesim\world_captures\{0}\run.json" -f $RunId)
        $arguments = @((Join-Path $PSScriptRoot 'import_world_captures.py'),
            '--run', $runPath, '--data-root', $dataRoot)
        if ($StagePreview) { $arguments += '--stage-preview' }
        Push-Location $root
        try {
            & python @arguments
            if ($LASTEXITCODE -ne 0) { throw "Importer validation failed; manifest was not published." }
        } finally { Pop-Location }
        Write-Output "COMPLETE: validated full capture imported; original restoration verified."
        exit 0
    }
    if ((Get-Date) - $lastAdvance -gt [TimeSpan]::FromMinutes(5)) {
        $heartbeat = Get-Content $heartbeatPath -Raw | ConvertFrom-Json
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        if ($now - [long]$heartbeat.writtenAt -gt 90) {
            throw "Server heartbeat stale: paused/closed/loading. Durable run retained; operator intervention needed."
        }
        throw "No result progress for five minutes; inspect durable phase before retry."
    }
    Start-Sleep -Seconds ([Math]::Max(5, $PollSeconds))
}
