# Windows desktop on GitHub Actions

`windows-desktop.yml` runs a **licensed** Windows desktop on a GitHub-hosted
Windows runner, reachable over RDP through Tailscale, with the user profile
backed up to the same encrypted rclone remote as the Linux variant.

There is no nested VM, no downloaded ISO and no activation step. `windows-latest`
is already a licensed, activated Windows Server image that GitHub provides —
running a pirated build would add risk (cracked ISOs are a malware vector) for
zero benefit, and a nested VM can't run usefully on the Linux runner anyway
(no `/dev/kvm`, so it would fall back to unusably slow emulation).

---

## Read this first: what latency is actually achievable

You asked for **0–10 ms**. I have to be straight with you: that is not
physically possible for this setup, and the reason is distance, not tuning.

- GitHub-hosted runners run in **Microsoft Azure**, and on a standard runner
  **you do not get to choose the region** — GitHub places the job. For most
  accounts that lands in the US.
- From India to a US datacenter, the network round-trip alone is roughly
  **180–250 ms**. Light in fibre travels ~5 µs per km, and real internet
  routing takes detours, so no amount of server tuning beats that.
- RDP then adds encode/decode and display, typically another 10–30 ms.

So a realistic figure is **~200–280 ms** of interactive latency, which feels
noticeably laggy. The tuning in `tune-rdp.ps1` removes every *added* millisecond
(UDP transport, low crypto, no animations, low colour depth), but it cannot
remove the ~200 ms of travel.

**10 ms is a LAN number.** To actually get single-digit-to-low-double-digit
latency you need the machine close to you — an Indian cloud region. Options,
best to worst for you:

| Option | Typical RTT from India | Notes |
|---|---|---|
| Cloud VM in an Indian region (Azure Central/South India, AWS Mumbai, E2E, DigitalOcean BLR) | **5–30 ms** | Persistent disk, no 6h cap, real desktop Windows. This is the only way to hit your target. |
| Self-hosted runner on an Indian VM | 5–30 ms | Same as above; keeps the Actions-style chain. |
| GitHub-hosted runner (this workflow) | **180–250 ms** | Free and simple, but far away. |

If low latency is the actual goal, the honest recommendation is a cloud VM in
India, not a GitHub runner. This Windows workflow is the best that can be done
*within* GitHub Actions.

---

## Secrets

Yes, it's a public repo — but **public repos do not expose Actions secrets.**
"Public" only means the *code* is public. Secrets live outside the repo,
encrypted, are injected only into a run, and are masked in logs. The thing you
must never do is commit a credential *as a file* — which is exactly what
`scripts/set-secrets.sh` avoids.

That said, you cannot have a reachable, persistent desktop with **zero**
secrets. Two are genuinely required:

| Secret | Required? | What it is / why |
|---|---|---|
| `TS_AUTHKEY` | **Yes** | Tailscale auth key. Runners have no inbound ports, so this is the only way you can reach the desktop. No key → unreachable. |
| `DESKTOP_PASSWORD` | **Yes** | The RDP login password. Windows enforces complexity: 8+ chars, upper + lower + digit. |
| `RESTART_PAT` | Optional | Fine-grained PAT (Actions: read+write). Without it the chain stops after 6h and you restart manually. |
| `RCLONE_CONFIG` | Optional | Your encrypted rclone remote. Without it every session starts with a blank profile (no persistence). |

Set them with the helper (values are read hidden, never written to disk):

```bash
gh auth login
./scripts/set-secrets.sh vot1122/cloud-desktop
```

The same four names are shared with the Linux workflow — you set them once.

---

## Client settings (these matter as much as the server)

In your RDP client, favour speed over quality — you said quality doesn't matter:

- **Resolution:** set 1280×720 (or "Match window"). You can drop to 1024×640 if
  it feels heavy; the smaller the framebuffer, the less to encode and send.
- **Colour depth:** 16-bit is the fastest. 24-bit if you want it to look normal.
- **Experience / Performance tab:** uncheck *everything* — wallpaper, font
  smoothing, desktop composition, animations, visual styles, menu/window
  animation. Then pick "Modem (56 kbps)"-style optimisation if offered.
- **Make sure UDP is used.** If your client shows connection info, a UDP/transport
  path means much lower latency than TCP. (This is what `SelectTransport=0`
  enables server-side.)
- **Verify you're on a direct WireGuard path, not a DERP relay.** From a machine
  on your tailnet: `tailscale ping cloudpc-win`. A `via DERP` result adds a big
  hop — a direct path (`via <ip>:41641`) is what you want.

Connect to `cloudpc-win.<your-tailnet>.ts.net:3389`, user `runneradmin`,
password = your `DESKTOP_PASSWORD`.

---

## How it differs from the Linux variant

- **No package install step.** The Windows image is prebuilt, so there's no
  ~5-minute apt phase to cache — boot is inherently quicker.
- **Persistence** covers `C:\Users\runneradmin` (minus caches), synced to
  `crypt1:winhome`. The Linux one uses `crypt1:home`.
- **Latency tuning is registry-based** (`tune-rdp.ps1`) rather than xrdp.ini.
- **Backups run at below-normal priority** — Windows has no `ionice`, so the
  snapshot process is dropped to `BelowNormal` and the child rclone inherits it.

## Caveats

- It's Windows **Server**, not consumer Windows 11. Most desktop apps run, but
  some that insist on a client SKU may not.
- No GPU — everything is software-rendered.
- Same 6-hour hard cap and same off-label-use status as the Linux workflow.
- Changing `runneradmin`'s password is fine, but if you RDP in *while* a job is
  running you share the machine with the Actions job; cancel the job when done.
