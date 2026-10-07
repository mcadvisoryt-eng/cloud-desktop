# CONNECT — how to reach the desktops

Everything you need to get in. No secret values are written here — only where
they go.

## Before you start

1. Install **Tailscale** on the device you'll connect from (Windows, macOS,
   iOS, Android, Linux) and log in once to your tailnet.
2. In the repo: **Settings → Secrets and variables → Actions**, add
   `TS_AUTHKEY` and `DESKTOP_PASSWORD` (see the table below). The desktops
   cannot be reached without these.
3. Actions tab → pick a workflow → **Run workflow**.

## The desktops

| | Linux (XFCE) | Windows | Android |
|---|---|---|---|
| Workflow | `cloud-desktop` | `windows-desktop` | `android-desktop` |
| Host (MagicDNS) | `cloudpc.<your-tailnet>.ts.net` | `cloudpc-win.<your-tailnet>.ts.net` | `cloudpc-android.<your-tailnet>.ts.net` |
| Port | 3389 | 3389 | 3200 (serve-avd) / 6080 (noVNC) / 5900 (VNC app) / 5555 (adb) |
| Username | `pc` | `pc` | — |
| Password | `DESKTOP_PASSWORD` | `DESKTOP_PASSWORD` | — |
| Protocol | RDP (xrdp) | RDP | noVNC (VNC in the browser) |

Replace `<your-tailnet>` with your tailnet name (shown in the Tailscale admin
console, e.g. `tailxxxxx.ts.net`). You can also use the tailnet IP printed in
the run log (`::notice::... ready at <ip>`).

## Secrets

| Secret | Required | Purpose |
|---|---|---|
| `TS_AUTHKEY` | **Yes** | Tailscale auth key — the only way in; runners have no open ports. |
| `DESKTOP_PASSWORD` | **Yes** | RDP login password. Windows needs 8+ chars, upper + lower + digit. |
| `RESTART_PAT` | Optional | Fine-grained PAT (Actions: read+write) to chain the next session past 6h. |
| `RCLONE_CONFIG` | Optional | Encrypted rclone remote for profile persistence. |

Set them safely (values read hidden, never written to disk):

```bash
gh auth login
./scripts/set-secrets.sh vot1122/cloud-desktop
```

## Make it fast

In your RDP client, favour speed over quality:

- Resolution **1280×720** (or "match window"); drop to 1024×640 if heavy.
- Colour depth **16-bit**.
- Experience/Performance: untick wallpaper, font smoothing, animations,
  desktop composition, visual styles.
- Check you're on a **direct** WireGuard path, not a DERP relay:
  `tailscale ping cloudpc-win` — a `via DERP` reply adds a big hop.

> Reminder: the runner's Azure region is not selectable, so from India expect
> ~180–250 ms of network round-trip. See `WINDOWS.md` for the honest latency
> picture and the cloud-VM alternative that actually reaches low latency.
