# Repository structure

`mcadvisoryt-eng/cloud-desktop` — a **free, self-restarting cloud desktop** built
entirely on GitHub-hosted Actions runners. No credit card, no paid tier, no VM
provider. Everything is public-repo Actions minutes.

Two desktops, one per workflow:

| Desktop | Workflow | Runner | Hostname | Transport |
|---|---|---|---|---|
| Linux (XFCE) | `desktop.yml` | `ubuntu-latest` | `cloudpc` | RDP, port 3389 |
| Windows Server 2025 | `windows-desktop.yml` | `windows-latest` | `cloudpc-win` | RDP, port 3389 |

Both are reachable only over the **Tailscale** tailnet (`tail996723.ts.net`).
RDP user is `pc` on both; the password is the `DESKTOP_PASSWORD` secret.

---

## Directory layout

```
.github/workflows/
  desktop.yml             Linux desktop: XFCE over xrdp, session loop, snapshots
  windows-desktop.yml     Windows desktop: RDP, Chrome + extensions, customisation
  maintenance.yml         Tailnet housekeeping + the watchdog (scheduled)
  verify.yml              End-to-end check: tailnet, RDP screenshot, backups

scripts/
  run-session.sh          Linux session loop: xrdp health, periodic snapshot, pre-queue
  snapshot.sh             Linux: mirror /home/pc -> crypt1:home (rclone), heartbeat
  tune-xrdp.py            Rewrites xrdp.ini + xfwm4.xml for low latency
  windows-session.ps1     Windows session loop: health, periodic snapshot, pre-queue
  windows-snapshot.ps1    Windows: profile -> crypt1:winhome; Chrome -> crypt1:chrome
  tune-rdp.ps1            Windows: RDP + desktop effects tuning
  set-secrets.sh          Push the required secrets with `gh` in one go
  provision-cloudvm.sh    Optional: provision an India-region KVM VPS (see CLOUD-VM.md)

Docs (repo root)
  README.md               Start here: what this is, quick connect
  STRUCTURE.md            This file
  CUSTOM-ISO.md           Custom / modified Windows images: what is possible
  CONNECT.md              How to connect from Windows, macOS, Android
  SECRETS.md              Every secret, what it is for, how to create it
  TUNING.md               Latency work: what was tuned and why
  WINDOWS.md              Windows-specific notes (Server quirks, apps, RDP)
  RCLONE.md               The encrypted backup layout in Google Drive
  TUNNEL.md               Tailscale setup, hostnames, ACLs
  MOBILE.md               Using it from a phone
  CLOUD-VM.md             The India-region VPS route for real low latency
  STATUS.md               Running log of what was tested and what broke
```

---

## Anatomy of a session

Both desktops follow the same lifecycle. A run is one **session** (~5.5 hours),
and sessions hand off to each other so the desktop appears continuous.

1. **Guard** — if an older session is still winding down, cancel it and keep the
   newest. (It used to cancel *itself*, which caused outages; fixed.)
2. **Provision** — create the `pc` user, install the desktop stack, write the
   session config.
3. **Restore** — pull the previous profile back from the encrypted Drive remote.
4. **Tailnet** — claim the hostname (deleting any stale node of the same name),
   then join Tailscale.
5. **Tune** — xrdp/RDP and desktop settings for latency.
6. **Session loop** — run for `SESSION_MINUTES`, health-checking the display
   server every 15s, snapshotting every 30 minutes.
7. **Pre-queue** — shortly before the end, dispatch the next session so the
   handover pays no queue latency.
8. **Final backup** — `if: always()`, so a normal end still snapshots.

### Keeping it alive (three layers)

- **Hand-off** — each session pre-queues the next (`run-session.sh`,
  `windows-session.ps1`). This is the reliable layer.
- **Watchdog** — `maintenance.yml` runs on a schedule, starts a session if none
  is running or queued, and cancels wedged runs.
- **Daily safety net** — both desktop workflows have a `cron` at 22:30 UTC
  (04:00 IST) in case the PAT chain ever breaks.

GitHub **delays scheduled workflows heavily** — in practice the watchdog fires
every few hours, not on the minute. That is a GitHub limitation, not a setting.

---

## Storage layout

Backups go to Google Drive through **rclone**, into an **encrypted** (crypt)
remote, so the contents are unreadable at rest.

```
gdrive:cloud-desktop/            <- the crypt remote's target
  crypt1:home                    Linux /home/pc
  crypt1:winhome                 Windows C:\Users\pc
  crypt1:chrome                  Chrome profile (lock-safe copy, see below)
  crypt1:trash/<stamp>           every replaced/deleted file, kept 7 days
  crypt1:logs/                   heartbeat, failure logs, verification reports
```

**Why `crypt1:chrome` exists:** rclone cannot read files Chrome holds open —
`Preferences`, `Login Data`, `Local State`, `Cookies` — which are exactly the
files that carry extension state and logins. So the Chrome profile is captured
separately with `robocopy /B` (backup mode can read locked files) and pushed to
its own remote, then restored into the profile each session.

---

## Secrets

Set in **Settings → Secrets and variables → Actions**. Full detail in
`SECRETS.md`.

| Secret | Used for |
|---|---|
| `TS_AUTHKEY` | joining the tailnet |
| `TS_API_KEY` | Tailscale API: list/delete stale nodes, resolve IPs |
| `DESKTOP_PASSWORD` | the `pc` password for RDP (both desktops) |
| `RESTART_PAT` | `gh workflow run` / `gh run cancel` — the hand-off and watchdog |
| `RCLONE_CONFIG` | the encrypted Google Drive remote |

The repo is **public by design** (free Actions minutes). Secrets are never in
the tree; they are only referenced as `${{ secrets.* }}`.

---

## Concurrency

Each desktop has its own `concurrency` group with `cancel-in-progress: false`,
so a live session is never killed by an overlapping trigger. The trade-off is
that a wedged session can block the queue — which is what the watchdog and the
guard's "keep the newest" logic exist to clear.

---

## Known limits

- **6-hour job cap.** Sessions are 345 minutes, comfortably inside it.
- **Runner region is not selectable** on standard runners, so RDP latency is
  whatever the distance to the runner's region gives you. `CLOUD-VM.md` covers
  the only real fix (an India-region host).
- **Runners are ephemeral.** Nothing survives except what reaches the encrypted
  Drive remote.
- **Scheduled workflows are unreliable** (see above).
