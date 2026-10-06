# windows-session.ps1 — keep the desktop alive for SESSION_MINUTES, snapshot
# periodically, and pre-queue the next runner shortly before this one ends.
#
# Latency / availability notes:
#   * RDP is health-checked every HealthEverySec (15 s) and the service is
#     restarted within seconds if it dies.
#   * ~10 min before the end the next runner is pre-queued, so the handoff
#     does not pay the trigger + queue wait (and survives a cancellation).
param(
    [int]$SessionMinutes    = 330,
    [int]$SnapshotEveryMin  = 30,
    [int]$HealthEverySec    = 15,
    [int]$PrequeueBeforeMin = 10
)
$ErrorActionPreference = 'Continue'

if ($env:SESSION_MINUTES)    { $SessionMinutes   = [int]$env:SESSION_MINUTES }
if ($env:SNAPSHOT_EVERY_MIN) { $SnapshotEveryMin = [int]$env:SNAPSHOT_EVERY_MIN }

$start     = Get-Date
$deadline  = $start.AddMinutes($SessionMinutes)
$lastSnap  = $start
$prequeued = $false
Write-Host "::notice::Windows session started. Running ${SessionMinutes}m, snapshot every ${SnapshotEveryMin}m, health check every ${HealthEverySec}s."

function Test-RdpUp {
    [bool](Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue)
}

while ((Get-Date) -lt $deadline) {
    # Keep RDP alive — cheap check, runs often.
    if (-not (Test-RdpUp)) {
        Write-Host "::warning:: RDP is not listening — restarting TermService"
        Restart-Service -Name TermService -Force -ErrorAction SilentlyContinue
    }

    # Pre-queue the next runner before this session ends.
    $remaining = ($deadline - (Get-Date)).TotalMinutes
    if ((-not $prequeued) -and ($remaining -le $PrequeueBeforeMin) -and $env:GH_TOKEN -and $env:GH_REPOSITORY) {
        gh workflow run windows-desktop.yml --repo $env:GH_REPOSITORY 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Next session pre-queued ($([math]::Round($remaining,1))m left)."
            $prequeued = $true
        }
    }

    # Snapshot when due.
    if (((Get-Date) - $lastSnap).TotalMinutes -ge $SnapshotEveryMin) {
        Write-Host "Periodic checkpoint..."
        & "$PSScriptRoot\windows-snapshot.ps1"
        $lastSnap = Get-Date
    }

    Start-Sleep -Seconds $HealthEverySec
}
Write-Host "Session loop complete."
