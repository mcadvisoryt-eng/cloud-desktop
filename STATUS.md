# STATUS.md — what exists, what's verified, what's still open

Last updated: 2026-10-08 (late evening IST).

## The three things

| Workflow | Host name | What it is | How you use it |
|---|---|---|---|
| `desktop.yml` | `cloudpc` | Linux XFCE desktop **+ a preinstalled Android emulator** | RDP (Windows App): user `pc`, `DESKTOP_PASSWORD` |
| `windows-desktop.yml` | `cloudpc-win` | Windows Server desktop | RDP: user `pc`, `DESKTOP_PASSWORD` |
| `maintenance.yml` | — | housekeeping: list/clean tailnet devices, KVM probe, backup check | manual |

Deleted as non-working: `android-desktop.yml` (redroid), `android-emulator.yml`
(standalone, broken web viewers), `kvm-probe.yml`.

`verify.yml` is the test harness (below). A cron runs it hourly and reports.

## How verification works (this is the important bit)

The sandbox cannot reach the tailnet, but a **runner can**. `verify.yml`:

1. Resolves each host's **tailnet IP from the Tailscale API** — it never uses
   MagicDNS names, because joining with `--accept-dns=false` (so the runner's own
   DNS is untouched) disables MagicDNS.
2. Joins the tailnet as `cloudpc-verify` (temporary, ephemeral).
3. Tests TCP reachability of `cloudpc:3389`, `cloudpc-win:3389`,
   `cloudpc-android:3389`, `cloudpc:5555`.
4. RDPs into `cloudpc` with `xfreerdp` and screenshots the result.
5. Attaches to the Android emulator over adb and screenshots it.
6. Checks backup freshness (newest `crypt1:trash` stamps, and any failure logs).

Screenshots are printed as **base64 wrapped at 76 chars** between
`screenshot base64 begin/end` markers, so they can be reassembled from the log
(GitHub truncates unwrapped long lines, which broke the first attempt).

## Verified working

- **`cloudpc:3389` is reachable** — xrdp is listening. (Tested 2026-10-08 17:23.)
- **Backups are landing** — `crypt1:trash` stamps every ~30 min, most recent
  17:14. `crypt1:home` 797 MiB, `crypt1:android` 7.8 GiB.
- **KVM is present on the runner** — `/dev/kvm`, `vmx`, `kvm_intel`, `nested=Y`
  (proven by the `kvm` action in maintenance.yml; the docs claim this is a
  larger-runner feature and they are wrong for this host).
- **The Android emulator's SDK + AVD build successfully** on the Linux desktop
  (step "Install the Android emulator + create an AVD" goes green), and it now
  uses the `google_apis_playstore` image, so it has the Play Store.
- **winget + Chocolatey** are set up on the Windows desktop.
- **The XFCE session starts and survives** — verified by the desktop's own
  self-test, which launches `startxfce4` on a scratch display and checks it's
  still running: `XFCE SESSION STARTED OK` / `xfce4-session` pid present
  (2026-10-08 17:53). This is the fix that matters — the `XDG_RUNTIME_DIR`
  correction resolved the "Unable to determine failsafe session name" abort.
- **Tailnet names are clean** — `cloudpc`, `cloudpc-win`, `cloudpc-android`, no
  `-1`/`-2` suffixes (hostname-claim works).

## Known open issues

- **The RDP *client* test is broken, not the desktop.** `xfreerdp` into a
  headless Xvfb prints its banner and then hangs with no error, producing a
  blank screenshot. Since the desktop's own self-test proves the session starts,
  this is a harness problem — but it means we have not yet seen a screenshot of
  the live RDP session. Worth fixing so the hourly check can see the screen.
- **The emulator's adb is not reachable over the tailnet** — port 5555 is
  refused externally because the emulator binds it to localhost. That's fine:
  the emulator is meant to be seen *on the desktop* over RDP, not via adb.
- **`cloudpc-android` still appears in the tailnet** as an online node even
  though its workflow was deleted — a leftover that will expire; harmless.

## Fixes made along the way (for the record)

| Symptom | Cause | Fix |
|---|---|---|
| VNC always black | apt scrcpy is 1.25; `--no-audio` doesn't exist until 2.0, so scrcpy exited instantly | probe `--help` and pass only supported flags |
| XFCE "Unable to determine failsafe session name" | `XDG_RUNTIME_DIR` pointed at the runner's uid, so dbus refused to start → no xfconfd | `.xsession` now sets `XDG_RUNTIME_DIR=/run/user/$(id -u)` |
| URL changed every run | Linux desktop had no hostname-claim step; a prefix match would have deleted the other three | claim by **exact short name** (`^cloudpc(-[0-9]+)?$`) |
| Android backup failed every time | `/data/tombstones` written mid-read → "corrupted on transfer" | excluded `tombstones/**` and `anr/**` |
| Restore took an hour | rclone enumerated the whole encrypted tree | restore only `data/ app/ system/ misc/ local/ user/`, capped at 10 min |
| `.xsession` kept reverting | the home restore re-clobbered it each run | write it **after** the restore |
| verify found nothing | joined with `--accept-dns=false`, so MagicDNS names didn't resolve | resolve IPs via the Tailscale API |
| screenshots unusable | GitHub truncates long log lines | wrap base64 at 76 chars |

## Next steps

1. Get the RDP screenshot to render — try `xfreerdp` with `/sec:nla`,
   `/kbd:0`, and a longer wait, or drive it with `xdotool`; alternatively test
   the session from the desktop side by having the desktop itself run
   `xdpyinfo`/`xdotool` inside the xrdp session and log the result.
2. Confirm the emulator window actually appears in the XFCE session.
3. Consider Google's official emulator container
   (`us-docker.pkg.dev/android-emulator-268719/images/...`) as a sturdier
   emulator base if the local AVD proves flaky.


---

## Update — 2026-10-09 (overnight)

- **The user still sees the XFCE failsafe error over RDP**, yet the desktop's own
  self-test reports `XFCE SESSION STARTED OK`. So the failure is specific to the
  **xrdp login path** (`startwm.sh -> /etc/X11/Xsession -> ~/.xsession`), not to
  XFCE itself.
- `desktop.yml` now runs a **local RDP self-test on that exact path** and writes
  the result to `~/selftest.log`, which the home backup picks up. Read it with
  the maintenance workflow's `backup` action:
  `rclone cat crypt1:home/selftest.log`.
- **GitHub discards a cancelled step's buffered output** — that is why earlier
  attempts to read the self-test from the run log came back empty. Persisting it
  to a file was the fix for the *diagnostic*, not for the desktop.
- `xfreerdp` in a headless Xvfb hangs (banner, then nothing) in both the verify
  workflow and the self-test. stdin is now redirected from /dev/null; if it
  still hangs, the next suspect is the security-layer negotiation.
- Open item: decide whether to keep the local emulator AVD or switch to Google's
  official emulator container.
