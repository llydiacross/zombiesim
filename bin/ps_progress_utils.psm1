Set-StrictMode -Version Latest

function Write-ZMLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = 'INFO',
        [string]$Step = ''
    )

    $prefix = "[ZombieSim][$Level]"
    if (-not [string]::IsNullOrWhiteSpace($Step)) {
        $prefix = "$prefix[$Step]"
    }

    $line = "$prefix $Message"
    Write-Host $line
    Write-Verbose $line
}

function Write-ZMProgress {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Activity,
        [Parameter(Mandatory = $true)]
        [string]$Status,
        [int]$PercentComplete = 0,
        [string]$Step = '',
        [switch]$Completed
    )

    if ($Completed) {
        Write-Progress -Activity $Activity -Completed
        if (-not [string]::IsNullOrWhiteSpace($Status)) {
            Write-ZMLog -Message $Status -Level 'DONE' -Step $Step
        }
        return
    }

    Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
    if (-not [string]::IsNullOrWhiteSpace($Step)) {
        Write-ZMLog -Message $Status -Level 'PROGRESS' -Step $Step
    }
}

Export-ModuleMember -Function Write-ZMLog, Write-ZMProgress
