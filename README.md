# cloud-desktop

A personal remote desktop you can reach from any device over Tailscale, with an
encrypted backup of your home directory. There are four ways to run it — pick
by how much latency you can tolerate (or whether you want a real Android phone
in the cloud).

| Option | Where it runs | RTT from India | Cost | Docs |
|---|---|---|---|---|
| **Linux on GitHub Actions** | Ephemeral Ubuntu runner | ~180–250 ms | free (public repo) | `TUNING.md` |
| **Windows on GitHub Actions** | Ephemeral Windows runner | ~180–250 ms | free (public repo) | `WINDOWS.md` |
| **Android on GitHub Actions** | redroid container (full Android) | ~180–250 ms | free (public repo) | `MOBILE.md` |
| **Android (emulator)** | Official AVD on a KVM-accelerated runner | ~180–250 ms | free (public repo) | `TUNNEL.md` |
| **Cloud VM in India** ⭐ | Your own VM in an Indian region | **~5–30 ms** | free tier or ~$5–25/mo | `CLOUD-VM.md` |

> **Latency, honestly.** 0–10 ms is a LAN number. GitHub's runners live in Azure
> in a region you can't choose (usually the US), so from India the round-trip is
> ~180–250 ms before RDP even encodes a frame. If low latency is the goal, the
> Indian-region VM is the only one of these that gets close. Everything else is
> tuned to remove the latency that *is* under our control.

## Start here

1. Read **`SECRETS.md`** and add the two required secrets (`TS_AUTHKEY`,
   `DESKTOP_PASSWORD`) — nothing works without them.
2. Pick your option above and read its doc.
3. For the Actions options: Actions tab → the workflow → **Run workflow**.
4. Connect using **`CONNECT.md`** (host, port, user).

## What's here

```
.github/workflows/
  desktop.yml            Linux desktop on a GitHub runner
  windows-desktop.yml    Windows desktop on a GitHub runner
  android-desktop.yml    Full Android (redroid) on a GitHub runner
  android-emulator.yml   Full Android (official emulator, KVM-accelerated)
  maintenance.yml        Tailnet housekeeping: list/clean devices, probe KVM
scripts/
  run-session.sh         Linux session loop (health check, snapshot, pre-queue)
  snapshot.sh            Linux encrypted backup (idle-priority rclone)
  tune-xrdp.py           xrdp.ini latency tuning
  tune-rdp.ps1           Windows RDP latency tuning
  windows-session.ps1    Windows session loop
  windows-snapshot.ps1   Windows encrypted backup
  provision-cloudvm.sh   Provision an Ubuntu VM as the desktop (Indian region)
  set-secrets.sh         Set the Actions secrets safely via the gh CLI
  android-snapshot.sh    Android (redroid) encrypted backup
  android-restore.sh     Scoped, time-capped Android restore
  android-excludes.txt   Caches/dalvik/oat kept out of backup + restore
  emulator-session.sh    Emulator session loop + viewers
TUNING.md   Linux/Actions latency tuning notes
TUNNEL.md   The transport: Tailscale direct vs DERP, Cloudflare's video ban, WebRTC
WINDOWS.md  Windows variant + the full latency picture
MOBILE.md   Full Android (redroid) on a runner, viewed in a phone browser
CLOUD-VM.md Indian-region VM (the low-latency path)
SECRETS.md  What to add and how to get each value
CONNECT.md  How to reach the desktops
```

## Honest warnings

- The GitHub Actions options are **off-label use** of Actions. GitHub's terms
  say hosted runners are for building/testing/deploying the repo's software;
  a personal desktop is out of scope, and enforcement can range from job
  termination to losing the repo or account. Keep it modest.
- There's a **gap between Actions sessions** (queue + boot + restore). The
  chain and pre-queue shrink it, but it isn't zero.
- The **6-hour cap is a hard kill** on Actions. Data changed since the last
  snapshot can be lost. (The cloud VM has no such cap.)
- Secrets **rotate** — `TS_AUTHKEY` and `RESTART_PAT` expire; refresh them.
- The cloud VM is **yours to secure**: patch it, and don't expose RDP to the
  public internet — use Tailscale.
