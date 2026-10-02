<#
.SYNOPSIS
Sends commands through the development console bridge and waits for the acknowledgement.

.DESCRIPTION
Writes a fresh request to content/data_static/consolecommands.txt and polls Garry's Mod DATA for the matching
result. The server writes a heartbeat about once per second while it ticks; a stale heartbeat means the game is
paused (Escape menu in singleplayer), still loading, or hung, so the script stops early instead of waiting blindly.
Requests containing changelevel also wait for the reloaded map to tick again.

Exit codes: 0 acknowledged, 2 server not ticking (ask the player whether the game is paused), 3 Garry's Mod not
running, 4 timed out while the server was ticking.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Command,

    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$RequestId = ('bridge-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff')),

    [ValidateRange(5, 600)]
    [int]$TimeoutSeconds = 60,

    [ValidateRange(2, 120)]
    [int]$StaleSeconds = 20,

    [ValidateRange(10, 600)]
    [int]$MapLoadSeconds = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$requestPath = Join-Path $repoRoot (Join-Path 'content' (Join-Path 'data_static' 'consolecommands.txt'))
$dataRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $repoRoot)) (Join-Path 'data' 'zombiesim')
$resultPath = Join-Path $dataRoot 'consolecommands.result.json'
$heartbeatPath = Join-Path $dataRoot 'consolecommands.heartbeat.json'

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

function Get-HeartbeatAge {
    $heartbeat = Read-JsonFile $heartbeatPath
    if ($null -eq $heartbeat -or $null -eq $heartbeat.PSObject.Properties['writtenAt']) { return $null }
    return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [double]$heartbeat.writtenAt
}

function Test-GameRunning {
    return $null -ne (Get-Process -Name 'gmod' -ErrorAction SilentlyContinue)
}

function Stop-Bridge([int]$Code, [string]$Message) {
    Write-Warning $Message
    exit $Code
}

if (-not (Test-GameRunning)) { Stop-Bridge 3 'Garry''s Mod is not running.' }

Set-Content -LiteralPath $requestPath -Encoding ASCII -Value (@("# request: $RequestId") + $Command)
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$result = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    $candidate = Read-JsonFile $resultPath
    if ($null -ne $candidate -and $candidate.requestId -eq $RequestId) { $result = $candidate; break }
    if (-not (Test-GameRunning)) { Stop-Bridge 3 'Garry''s Mod exited before acknowledging the request.' }
    $age = Get-HeartbeatAge
    if ($null -ne $age -and $age -gt $StaleSeconds) {
        Stop-Bridge 2 ("The server has not ticked for {0}s. The game is probably paused (Escape menu) or loading; ask the player, then resend." -f [math]::Round($age))
    }
}
if ($null -eq $result) { Stop-Bridge 4 "Request '$RequestId' was not acknowledged within $TimeoutSeconds s although the server is ticking." }

if (@($Command | Where-Object { $_ -match '^\s*changelevel\s' }).Count -gt 0) {
    $acknowledgedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $loadDeadline = (Get-Date).AddSeconds($MapLoadSeconds)
    $loaded = $false
    while ((Get-Date) -lt $loadDeadline) {
        Start-Sleep -Seconds 1
        $heartbeat = Read-JsonFile $heartbeatPath
        if ($null -ne $heartbeat -and $null -ne $heartbeat.PSObject.Properties['loadedAt'] -and [double]$heartbeat.loadedAt -ge $acknowledgedAt) { $loaded = $true; break }
        if (-not (Test-GameRunning)) { Stop-Bridge 3 'Garry''s Mod exited during the level change.' }
    }
    if (-not $loaded) { Stop-Bridge 2 "The map did not resume ticking within $MapLoadSeconds s after changelevel; it may be paused or still loading. Ask the player." }
}

$result | ConvertTo-Json -Depth 8
