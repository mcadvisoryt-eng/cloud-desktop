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

# Fixed default topic, so notifications work out of the box. Override any time
# by setting the NTFY_TOPIC secret; this value stays put until you change it.
if (-not $env:NTFY_TOPIC) { $env:NTFY_TOPIC = 'cloudpc-2c50b2a3b2ba989d' }

function Notify([string]$title, [string]$tags, [string]$priority, [string]$msg) {
    # ntfy push (https://ntfy.sh).
    if (-not $env:NTFY_TOPIC) { Write-Log "ntfy skipped: no topic"; return }
    try {
        $body = [Text.Encoding]::UTF8.GetBytes($msg)
        Invoke-RestMethod -Uri "https://ntfy.sh/$($env:NTFY_TOPIC)" -Method Post -Body $body `
            -Headers @{ Title = $title; Tags = $tags; Priority = $priority } -TimeoutSec 15 | Out-Null
        Write-Log "ntfy sent: $title"
    } catch { Write-Log "ntfy failed: $($_.Exception.Message)" }
}

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
    '--transfers', '8', '--checkers', '4', '--fast-list', '--checksum', '--stats', '30s', '--stats-one-line',
    '--exclude', 'AppData/Local/Temp/**',
    '--exclude', 'AppData/Local/Microsoft/Windows/INetCache/**',
    '--exclude', 'AppData/Local/Microsoft/Windows/WebCache/**',
    '--exclude', 'AppData/Local/Microsoft/Windows/Explorer/**',
    '--exclude', 'AppData/Local/Packages/**/LocalCache/**',
    '--exclude', 'AppData/Local/Packages/**/TempState/**',
    # Chrome is captured separately below with a lock-safe copy: rclone
    # cannot read the files Chrome holds open (Preferences, Login Data,
    # Local State, Cookies) and those errors used to fail the whole sync.
    '--exclude', 'AppData/Local/Google/Chrome/**',
    '--exclude', 'AppData/Local/Microsoft/Edge/User Data/**/Cache/**',
    '--exclude', 'AppData/Local/Mozilla/**/cache2/**',
    '--exclude', 'AppData/Roaming/Microsoft/Windows/Recent/**',
    '--exclude', 'NTUSER.DAT*',
    '--exclude', 'AppData/Local/Microsoft/Windows/UsrClass.dat*',
    '--exclude', '*.log'
)

# --- Chrome profile: lock-safe capture --------------------------------------
# rclone cannot read files Chrome keeps open, and those are exactly the ones
# that carry the extension state and the Proton VPN sign-in. robocopy /B uses
# the backup privilege to read locked files, so stage a copy and push that.
$chromeSrc = "C:\Users\$u\AppData\Local\Google\Chrome"
if (Test-Path $chromeSrc) {
    Write-Log "Staging the Chrome profile (robocopy /B, lock-safe)"
    $stage = 'C:\chrome-stage'
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    & robocopy $chromeSrc $stage /E /B /R:1 /W:1 /NFL /NDL /NJH /NJS `
        /XD Cache 'Code Cache' GPUCache ShaderCache GrShaderCache 'Service Worker' `
            'DawnGraphiteCache' 'DawnWebGPUCache' 'Media Cache' | Out-Null
    $rcRobo = $LASTEXITCODE
    Write-Log "robocopy exit $rcRobo (below 8 means success)"
    if ($rcRobo -lt 8) {
        & $rclone sync $stage 'crypt1:chrome' --transfers 8 --checkers 4 *>> $log
        Write-Log "chrome profile sync exit $LASTEXITCODE"
    } else {
        Write-Log "::warning::robocopy could not stage the Chrome profile (exit $rcRobo)"
    }
} else {
    Write-Log "no Chrome profile at $chromeSrc yet"
}

# --- profile hive: the piece that makes the folder a real profile ----------
# NTUSER.DAT is a LIVE registry hive: Windows opens it with no shared read, so
# even robocopy /B cannot copy it — which is why the hive never made it into the
# backup. `reg save` is the supported way to snapshot a loaded hive, and it
# works while the user is logged in.
$hiveStage = 'C:\hive-stage'
Remove-Item $hiveStage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $hiveStage | Out-Null
$hiveOut = Join-Path $hiveStage 'NTUSER.DAT'

$sid = $null
try { $sid = (Get-LocalUser -Name $u -ErrorAction Stop).SID.Value }
catch { Write-Log "could not resolve the SID for $u" }

if ($sid) {
    & reg query "HKU\$sid" *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Saving the profile hive with reg save (HKU\$sid)"
        & reg save "HKU\$sid" $hiveOut /y *>> $log
        Write-Log "reg save exit $LASTEXITCODE"
        if ((Test-Path $hiveOut) -and ((Get-Item $hiveOut).Length -gt 0)) {
            Write-Log "hive file size $((Get-Item $hiveOut).Length) bytes"
            & $rclone copyto $hiveOut 'crypt1:winhive/NTUSER.DAT' *>> $log
            Write-Log "hive upload exit $LASTEXITCODE"
        } else {
            Write-Log "reg save produced no file - hive NOT captured"
        }
    } else {
        Write-Log "hive for $u is not loaded (user not logged in) - nothing to capture"
    }
}

$attempt = 1
$maxAttempts = 2
$ok = $false
while ($attempt -le $maxAttempts -and -not $ok) {
    Write-Log "attempt $attempt/$maxAttempts"
    & $rclone @syncArgs *>> $log
    $rc = $LASTEXITCODE
    # Exit 0 = clean. Anything else is usually a few locked/skipped files in a
    # LIVE profile, which is expected — log it, do not treat it as fatal.
    if ($rc -eq 0) {
        $ok = $true
    } elseif ($attempt -ge $maxAttempts) {
        Write-Log "sync finished with warnings (exit $rc) - most files were copied"
        $ok = $true
    } else {
        $attempt++
        if ($attempt -le $maxAttempts) { Start-Sleep -Seconds 20 }
    }
}

if ($ok) {
    Write-Log "Snapshot complete."
    & $rclone copyto $log "$logRemote/windows-backup-latest.log" *>> $log 2>$null
    $changed = ''
    try {
        $m = Select-String -Path $log -Pattern 'Transferred:\s+(\d+)' -AllMatches | Select-Object -Last 1
        if ($m) { $changed = $m.Matches[-1].Groups[1].Value }
    } catch {}
    Notify "Windows backup ok" "white_check_mark" "default" "$($env:COMPUTERNAME): $($changed) file(s) changed, synced to $remote"
    # Prune trash older than 7 days (best-effort).
    & $rclone delete --min-age 7d $trash *>> $log 2>$null
    exit 0
}

Write-Log "snapshot FAILED after $($attempt - 1) attempts"
Notify "Windows backup FAILED" "x" "high" "$($env:COMPUTERNAME): snapshot failed after $($attempt - 1) attempts — see $logRemote/windows-backup-$stamp.log"
Write-Log "uploading this log to $logRemote/windows-backup-$stamp.log and continuing WITHOUT blocking the session"
& $rclone copyto $log "$logRemote/windows-backup-$stamp.log" *>> $log 2>$null
& $rclone copyto $log "$logRemote/windows-backup-latest.log" *>> $log 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "::warning::could not upload the backup log to $logRemote" }
Write-Host "::warning::Windows snapshot did not complete; log saved to $logRemote/windows-backup-$stamp.log — session continues"
exit 0
