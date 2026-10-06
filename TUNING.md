# TUNING — fastest response & lowest latency

This is a short guide to the changes made to the original repo, why they help,
and the one or two knobs you may want to flip depending on your network.

There are three separate things people mean by "latency" here, and each has a
different fix:

1. **Handoff latency** — the gap between one runner dying and the next desktop
   being reachable. Was ~5–8 min (queue + apt install + restore).
2. **Interactive latency** — how long a keystroke or click takes to appear on
   your screen while you work. This is the RDP/xrdp pipeline.
3. **Jitter** — the periodic stutter caused by a background backup competing
   with the desktop for CPU/disk.

---

## 1. Handoff latency (boot)

| Change | Effect |
|---|---|
| `actions/cache` on the downloaded `.deb` archives | Skips the ~4–6 min download/install of libreoffice + fonts + xfce4 on every runner. On a cache hit the install is seconds. |
| Home restore runs **in parallel** with the package install | The restore (minutes) now overlaps the install instead of waiting behind it. |
| rclone fetched as a **static binary** (no apt round-trip) | Available instantly, and lets the parallel restore start immediately. |
| `--transfers 16 --checkers 16` on restore | Restores a large home faster than the old 8/8. |
| Next runner **pre-queued ~10 min before the session ends** | When this session stops, the next run is already queued, so you don't pay the trigger + queue wait. It also means the chain now survives a *cancellation*, not just a crash. |

The cache key includes the workflow file hash, so editing the package list
invalidates it automatically. The cache is capped at 5 GB per repo by GitHub.

**Optional, bigger lever:** GitHub-hosted `ubuntu-latest` is a fixed size. If
you want more CPU/RAM for heavier work, a *larger runner* (paid) is the only
way to raise the ceiling; nothing in these scripts needs changing for that.

---

## 2. Interactive latency (xrdp)

All of this is applied by the workflow's "Tune xrdp + XFCE" step, which runs
`scripts/tune-xrdp.py` on `/etc/xrdp/xrdp.ini` (a line-based, section-confined,
idempotent editor) plus a couple of codec/theme tweaks.

**[Globals] keys set:**

| Key | Value | Why |
|---|---|---|
| `use_fastpath` | `both` | Carries input/output over the fastpath channel instead of the slower channel path. One of the biggest responsiveness wins. |
| `tcp_nodelay` | `true` | Disables Nagle, so a keystroke or small repaint leaves immediately instead of being coalesced. See the tradeoff below. |
| `tcp_keepalive` | `true` | Drops dead connections instead of hanging. |
| `bitmap_cache` / `bitmap_compression` | `true` | Reuse + compress tiles → less bandwidth, fewer redraws. |
| `bulk_compression` | `true` | Compresses bulk transfers. |
| `max_bpp` | `32` | Full colour; 32-bit is also what makes the client negotiate RFX well. |
| `new_cursors` | `true` | Client-side cursors, so the pointer doesn't lag behind. |
| `crypt_level` | `low` | The Tailscale link is already WireGuard-encrypted; RDP-level crypto is redundant CPU per frame. |

**[Xorg] backend:** `rfx_frame_interval=16`, `h264_frame_interval=16`,
`normal_frame_interval=16`. These set how long xorgxrdp waits before bundling
screen changes into a frame; the stock defaults are 16/32/40 ms. Lower = less
added latency, higher = less bandwidth.

**Codec:** on xrdp ≥ 0.10 the step sets `gfx.toml` `order = ["RFX", "H.264"]`.
On a GPU-less runner RemoteFX is consistently snappier for UI work than H.264
(the H.264 encoder is the bottleneck), so RFX is preferred.

**XFCE:** compositing, box-move/resize animations and cycle preview are turned
off in `xfwm4.xml`, and `.xsession` runs `xset s off -dpms` so the screen never
blanks. A compositor doubles every frame's cost; on RDP it is pure latency.

### The one tradeoff worth knowing

`tcp_nodelay=true` is right for interactive work — it minimises the latency of
small updates. It *can* reduce raw throughput on a high-bandwidth, high-RTT
link, where Nagle coalescing helps. If you ever see large redraws (photos,
full-screen video) crawl while typing feels fine, try this instead:

```
tcp_nodelay=false
tcp_send_buffer_bytes=262144
```

The line-based editor makes this easy: put it in the `GLOBALS` dict in
`scripts/tune-xrdp.py`, or just edit `/etc/xrdp/xrdp.ini` in a live session and
`sudo service xrdp restart`.

---

## 3. Jitter (backups)

`scripts/snapshot.sh` now runs rclone under `nice -n 19 ionice -c3` (idle CPU
and idle disk priority) with `--checkers 4`. The 30-minute snapshot no longer
competes with the desktop for the runner's CPU or disk, so your session stops
stuttering every time a backup fires. Correctness is unchanged: same `sync`,
same `--backup-dir` 7-day trash.

`scripts/run-session.sh` now health-checks xrdp **every 15 s** instead of once
per snapshot interval, so if xrdp ever dies it is restarted within seconds
rather than up to 30 minutes.

---

## Client-side tips (these matter as much as the server)

- **Use RemoteFX:** in Microsoft Remote Desktop / mstsc, pick the highest
  connection quality and 32-bit colour; xfreerdp: add `/rfx /gfx +glyph-cache`.
- **Turn off wallpaper, font smoothing and animations** in the client's
  Experience/Performance tab — they cost bandwidth and latency for no gain.
- **Check you're on a direct WireGuard path.** Tailscale falls back to a DERP
  relay when it can't hole-punch, which adds real latency. Run
  `tailscale ping <your-device>` from the desktop; a `via DERP` result means
  you're relaying. A direct path (`via <ip>:41641`) is what you want.

---

## What was intentionally left alone

- The off-label-on-GitHub-Actions nature of the project (see the README's
  honest warnings) — none of this changes that.
- The encrypted rclone backup model, the 7-day trash, the Tailscale auth, and
  the PAT chain. All preserved.
- The session length (`SESSION_MINUTES=330`) and GitHub's 6-hour hard cap.
