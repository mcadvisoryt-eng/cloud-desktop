# windows-snapshot.ps1 — mirror the user profile to the encrypted rclone remote.
# Runs at below-normal CPU priority so a backup never makes the desktop stutter
# (Windows has no ionice equivalent; the child process inherits this priority).
$ErrorActionPreference = 'Continue'

try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}

$remote = if ($env:REMOTE)       { $env:REMOTE }       else { 'crypt1:winhome' }
$trash  = if ($env:TRASH_REMOTE) { $env:TRASH_REMOTE } else { 'crypt1:trash' }
$stamp  = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$rclone = if (Test-Path 'C:\rclone\rclone.exe') { 'C:\rclone\rclone.exe' } else { 'rclone' }

$conf = Join-Path $env:APPDATA 'rclone\rclone.conf'
if (-not (Test-Path $conf)) {
    Write-Host "::warning:: no rclone.conf found; skipping snapshot"
    exit 0
}
$env:RCLONE_CONFIG = $conf

$u = if ($env:RDP_USER) { $env:RDP_USER } else { 'runneradmin' }
$src = "C:\Users\$u"
Write-Host "Snapshotting $src -> $remote (trash: $trash/$stamp)"

& $rclone sync $src $remote --backup-dir "$trash/$stamp" `
    --transfers 8 --checkers 4 --fast-list --stats 30s --stats-one-line `
    --exclude "AppData/Local/Temp/**" `
    --exclude "AppData/Local/Microsoft/Windows/INetCache/**" `
    --exclude "AppData/Local/Microsoft/Windows/WebCache/**" `
    --exclude "AppData/Local/Microsoft/Windows/Explorer/**" `
    --exclude "AppData/Local/Packages/**/LocalCache/**" `
    --exclude "AppData/Local/Packages/**/TempState/**" `
    --exclude "AppData/Local/Google/Chrome/User Data/**/Cache/**" `
    --exclude "AppData/Local/Microsoft/Edge/User Data/**/Cache/**" `
    --exclude "AppData/Local/Mozilla/**/cache2/**" `
    --exclude "AppData/Roaming/Microsoft/Windows/Recent/**" `
    --exclude "NTUSER.DAT*" `
    --exclude "AppData/Local/Microsoft/Windows/UsrClass.dat*" `
    --exclude "*.log"

# Prune trash older than 7 days.
& $rclone delete --min-age 7d $trash 2>$null
Write-Host "Snapshot complete."
exit 0
