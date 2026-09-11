[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromRemainingArguments)]
    [ValidateNotNullOrEmpty()]
    [string[]] $Command,
    [string] $RequestId = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RequestId)) {
    $RequestId = 'manual-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
}
if ($RequestId -notmatch '^[a-zA-Z0-9_-]+$') {
    throw 'RequestId may contain only letters, numbers, underscores, and hyphens.'
}

$commands = @($Command | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
if ($commands.Count -eq 0 -or @($commands | Where-Object { $_ -match '^#\s*request:' }).Count -gt 0) {
    throw 'Provide one or more server commands without a # request: line.'
}

$bridgePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'content\data_static\consolecommands.txt'
$contents = @('# request: ' + $RequestId) + $commands
Set-Content -LiteralPath $bridgePath -Value $contents -Encoding Ascii
Write-Output "Staged development-console request $RequestId."