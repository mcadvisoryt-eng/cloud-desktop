# TUNNEL.md — the transport, and why it decides everything

The Android desktop is only as good as the pipe carrying the video. This file
records what actually matters, because the obvious answer ("use Cloudflare
Tunnel") is the wrong one.

## The short version

| Transport | Latency cost | Verdict for streaming |
|---|---|---|
| **Tailscale, direct WireGuard path** | ~0 — as fast as the raw connection | **Best. Use this.** |
| Tailscale via **DERP relay** | ~6× less throughput, **+118 ms** | The thing to detect and avoid |
| Cloudflare Tunnel | +9–45 ms (forced edge hop) | Slower **and** ToS-prohibited for video |
| **WebRTC** (over a direct path) | Lowest for real-time media | The real upgrade — see below |

Measured numbers: a direct Tailscale path ran at 268 Mbit/s; the same path via
DERP fell to 42 Mbit/s with 118 ms added RTT (source: DoWithSudo, "Cloudflare
Tunnel vs Tailscale Subnet Router"). Cloudflare's own edge adds 9–18 ms, and its
**Self-Serve Terms Section 2.8 prohibit serving video through the free CDN**,
with automated bans for it (source: EastKode, Cloudflare/HomelabCompass
comparisons).

## Rule 1 — check direct vs DERP before blaming anything else

This is the single most common reason a tailnet "feels slow": NAT traversal
fails (very common on Indian mobile CGNAT and networks that block UDP) and every
packet silently goes through a shared relay in another country.

The workflows print `tailscale status` and `tailscale netcheck` at startup.
Look for:

- `tailscale ping <peer>` reporting `via <ip>:41641` → **direct, good**.
- reporting `via DERP(...)` → **relayed, bad**.
- `netcheck` saying UDP is blocked → that is why.

If it's relaying, the fixes are, in order: allow outbound UDP 41641 on your
network; prefer Wi-Fi over a UDP-hostile mobile carrier; or accept it.

## Rule 2 — do not use Cloudflare Tunnel for this

It adds latency rather than removing it, it's HTTP-first (non-HTTP is a
secondary mode), and streaming video through the free tier breaks their terms.
It solves "publish a web app to strangers", which is not our problem.

## Rule 3 — WebRTC is the real low-latency path

WebRTC is built for real-time media: it does its own NAT traversal, uses UDP,
and its receiver renders frames immediately instead of buffering them for
smoothness. That last point is huge — one team measured **~90 ms of latency
reduction at p50** just from disabling WebRTC's jitter/playout buffer (source:
Multi engineering blog, "Making Illegible, Slow WebRTC Screenshare Legible and
Fast").

For Android specifically, the pattern is: **scrcpy-server on the device →
WebRTC → browser**. Working implementations to draw on:

- **scrcpy-bridge** — Rust, hands scrcpy's H.264 NALs straight to WebRTC with
  **zero decode/re-encode**; targets **<150 ms LAN, <300 ms WAN**. Notes that the
  naive decode→re-encode approach capped at 10–15 fps.
- **webscreen** — self-hosted WebRTC streaming for Android over scrcpy;
  H.264/H.265, multi-finger touch, clipboard.
- **ws-scrcpy-web** — vanilla scrcpy-server, **WebCodecs only, no WASM
  fallbacks**; H.264/H.265/AV1; maintained fork of ws-scrcpy.
- **serve-emu** — scrcpy-server → WebSocket H.264 → WebCodecs, with useful
  defaults: `--max-fps 60`, `--bit-rate 8000000`, `--max-size 1280`.

## Rule 4 — for the emulator, the GPU mode matters more than the bitrate

If the emulator falls back to a software compositor (`llvmpipe`/`lavapipe`) the
guest caps at a janky ~20 fps and **no bitrate or transport setting can fix it**
(source: serve-emu README). GitHub runners have no GPU, so this is a real risk
here — the mitigation is to keep the resolution small and the frame rate honest.

Related: the emulator's **software** H.264 encoder sustains 60 fps only below
about **1 megapixel**. 540×960 is 0.5 MP, so our default is inside that budget;
raising the resolution past ~720p will cost frames.

## Rule 5 — the runner's bandwidth is not the bottleneck

Action runners have very fast pipes. The latency you feel is (a) the physical
distance to the runner's region and (b) the viewer's encode/decode pipeline. No
amount of tunnel engineering changes (a).

## What we do about it

- Every Android workflow prints the Tailscale **direct-vs-DERP** check, so we
  stop guessing.
- The browser viewers use **scrcpy's native H.264** (not screenshot polling) and
  decode with **WebCodecs/MSE** (hardware), never WASM or MJPEG.
- `TUNNEL.md` is the place to come back to when a stream feels slow: check the
  path first, then the viewer, then the resolution.

## Next step, if you want to go further

Wire a **WebRTC** viewer (scrcpy-bridge or webscreen) in place of the
WebSocket viewers. That is the one change that can plausibly take glass-to-glass
from ~300 ms toward ~150 ms, because it removes the WebSocket hop and the
receiver's smoothing buffer.
