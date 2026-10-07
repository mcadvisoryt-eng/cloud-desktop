# windows-snapshot.ps1 — mirror the user profile to the encrypted rclone remote.
# Runs at below-normal CPU priority so a backup never makes the desktop stutter
# (Windows has no ionice equivalent; the child process inherits this priority).
#
# Resilience rules (deliberate):
#   * A backup that does not complete must NEVER block the session.
#   * If it fails, we retry once, then write a log, upload that log to
#     <remote>:logs/ so you can read it later, and exit 0.
$ErrorActionPreference = 'Continue'

try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}

$remote    = if ($env:REMOTE)       { $env:REMOTE }       else { 'crypt1:winhome' }
$trash     = if ($env:TRASH_REMOTE) { $env:TRASH_REMOTE } else { 'crypt1:trash' }
$logRemote = if ($env:LOG_REMOTE)   { $env:LOG_REMOTE }   else { 'crypt1:logs' }
$stamp     = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$rclone    = if (Test-Path 'C:\rclone\rclone.exe') { 'C:\rclone\rclone.exe' } else { 'rclone' }
$log       = "$env:TEMP\windows-backup-$stamp.log"

$conf = Join-Path $env:APPDATA 'rclone\rclone.conf'
if (-not (Test-Path $conf)) {
    Write-Host "::warning:: no rclone.conf found; skipping snapshot"
    exit 0
}
$env:RCLONE_CONFIG = $conf

function Write-Log([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date).ToUniversalTime().ToString('HH:mm:ss'), $m
    Write-Host $line
    Add-Content -Path $log -Value $line
}

$u = if ($env:RDP_USER) { $env:RDP_USER } else { 'runneradmin' }
$src = "C:\Users\$u"
Write-Log "Snapshotting $src -> $remote (trash: $trash/$stamp)"

$syncArgs = @(
    'sync', $src, $remote, '--backup-dir', "$trash/$stamp",
    '--transfers', '8', '--checkers', '4', '--fast-list', '--stats', '30s', '--stats-one-line',
    '--exclude', 'AppData/Local/Temp/**',
    '--exclude', 'AppData/Local/Microsoft/Windows/INetCache/**',
    '--exclude', 'AppData/Local/Microsoft/Windows/WebCache/**',
    '--exclude', 'AppData/Local/Microsoft/Windows/Explorer/**',
    '--exclude', 'AppData/Local/Packages/**/LocalCache/**',
    '--exclude', 'AppData/Local/Packages/**/TempState/**',
    '--exclude', 'AppData/Local/Google/Chrome/User Data/**/Cache/**',
    '--exclude', 'AppData/Local/Microsoft/Edge/User Data/**/Cache/**',
    '--exclude', 'AppData/Local/Mozilla/**/cache2/**',
    '--exclude', 'AppData/Roaming/Microsoft/Windows/Recent/**',
    '--exclude', 'NTUSER.DAT*',
    '--exclude', 'AppData/Local/Microsoft/Windows/UsrClass.dat*',
    '--exclude', '*.log'
)

$attempt = 1
$maxAttempts = 2
$ok = $false
while ($attempt -le $maxAttempts -and -not $ok) {
    Write-Log "attempt $attempt/$maxAttempts"
    & $rclone @syncArgs *>> $log
    if ($LASTEXITCODE -eq 0) {
        $ok = $true
    } else {
        $attempt++
        if ($attempt -le $maxAttempts) { Start-Sleep -Seconds 20 }
    }
}

if ($ok) {
    Write-Log "Snapshot complete."
    # Prune trash older than 7 days (best-effort).
    & $rclone delete --min-age 7d $trash *>> $log 2>$null
    exit 0
}

Write-Log "snapshot FAILED after $($attempt - 1) attempts"
Write-Log "uploading this log to $logRemote/windows-backup-$stamp.log and continuing WITHOUT blocking the session"
& $rclone copyto $log "$logRemote/windows-backup-$stamp.log" *>> $log 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "::warning::could not upload the backup log to $logRemote" }
Write-Host "::warning::Windows snapshot did not complete; log saved to $logRemote/windows-backup-$stamp.log — session continues"
exit 0
